import http from 'node:http';
import express from 'express';
import cors from 'cors';
import { WebSocketServer, WebSocket } from 'ws';
import { loadConfig, type LLMConfig } from '../llm.js';
import * as orchestrator from '../frontal-orchestrator/index.js';
import { enrich, healthCheck } from '../brain-bridge.js';
import type { ChatMessage } from '../llm-client.js';

export interface ApiServerOptions {
  port: number;
  config: LLMConfig;
}

export function createServer({ port, config }: ApiServerOptions) {
  const app = express();
  app.use(cors());
  app.use(express.json());

  const sessions = new Map<string, ChatMessage[]>();

  // ── Health ──────────────────────────────────────────────────

  app.get('/health', (_req, res) => {
    res.json({ status: 'ok', brain: 'unknown' });
  });

  // ── Brain enrichment ────────────────────────────────────────

  app.post('/enrich', async (req, res) => {
    const { text, intensity } = req.body;
    if (!text) {
      res.status(400).json({ error: 'text is required' });
      return;
    }
    const ctx = await enrich(text, intensity ?? 0.5);
    res.json({ enrichment: ctx });
  });

  // ── Chat (dual-brain) ───────────────────────────────────────

  app.post('/chat', async (req, res) => {
    const { text, session_id } = req.body;
    if (!text) {
      res.status(400).json({ error: 'text is required' });
      return;
    }

    const sid = session_id ?? 'default';
    if (!sessions.has(sid)) sessions.set(sid, []);
    const history = sessions.get(sid)!;

    try {
      const result = await orchestrator.process(text, config, history);
      history.push({ role: 'user', content: text });
      history.push({ role: 'assistant', content: result.response });
      res.json({
        response: result.response,
        brain_context: result.brainContext,
        primary_lobe: result.primaryLobe,
      });
    } catch (err) {
      res.status(500).json({ error: err instanceof Error ? err.message : 'unknown' });
    }
  });

  // ── Chat stream (SSE) ───────────────────────────────────────

  app.post('/chat/stream', async (req, res) => {
    const { text, session_id } = req.body;
    if (!text) {
      res.status(400).json({ error: 'text is required' });
      return;
    }

    res.setHeader('Content-Type', 'text/event-stream');
    res.setHeader('Cache-Control', 'no-cache');
    res.setHeader('Connection', 'keep-alive');

    const sid = session_id ?? 'default';
    if (!sessions.has(sid)) sessions.set(sid, []);
    const history = sessions.get(sid)!;

    try {
      res.write(`data: ${JSON.stringify({ type: 'status', status: 'processing' })}\n\n`);

      const result = await orchestrator.process(text, config, history);
      history.push({ role: 'user', content: text });
      history.push({ role: 'assistant', content: result.response });

      res.write(`data: ${JSON.stringify({ type: 'result', ...result })}\n\n`);
    } catch (err) {
      res.write(`data: ${JSON.stringify({ type: 'error', error: err instanceof Error ? err.message : 'unknown' })}\n\n`);
    }

    res.end();
  });

  // ── Cortex endpoints (for Elixir brain LLM bridge) ──────────

  app.post('/cortex/left', async (req, res) => {
    const { text } = req.body;
    if (!text) {
      res.status(400).json({ error: 'text is required' });
      return;
    }
    try {
      const result = await orchestrator.process(text, config, [{ role: 'user', content: text }]);
      res.json({
        candidates: [{ action: result.response, expected_reward: 0.8, confidence: 0.7, reasoning: 'left_brain' }],
      });
    } catch (err) {
      res.status(500).json({ error: err instanceof Error ? err.message : 'unknown' });
    }
  });

  app.post('/cortex/right', async (req, res) => {
    const { text } = req.body;
    if (!text) {
      res.status(400).json({ error: 'text is required' });
      return;
    }
    try {
      const result = await orchestrator.process(text, config, [{ role: 'user', content: text }]);
      res.json({
        insight: { insight: result.response, confidence: 0.6, approach: 'creative' },
      });
    } catch (err) {
      res.status(500).json({ error: err instanceof Error ? err.message : 'unknown' });
    }
  });

  // ── Model info ──────────────────────────────────────────────

  app.get('/model', (_req, res) => {
    res.json({
      left: config.leftBrain,
      right: config.rightBrain,
    });
  });

  // ── Status ──────────────────────────────────────────────────

  app.get('/status', async (_req, res) => {
    const brainOnline = await healthCheck();
    res.json({
      brain: brainOnline ? 'online' : 'offline',
      left: config.leftBrain.provider + '/' + config.leftBrain.model,
      right: config.rightBrain.provider + '/' + config.rightBrain.model,
      sessions: sessions.size,
    });
  });

  // ── HTTP server + WebSocket ─────────────────────────────────

  const server = http.createServer(app);

  const wss = new WebSocketServer({ server, path: '/ws' });

  wss.on('connection', (ws) => {
    const wsSession: ChatMessage[] = [];

    ws.on('message', async (raw) => {
      let msg: { type: string; text?: string; command?: string };
      try {
        msg = JSON.parse(raw.toString());
      } catch {
        ws.send(JSON.stringify({ type: 'error', error: 'invalid JSON' }));
        return;
      }

      if (msg.type === 'command') {
        handleWsCommand(ws, msg.command ?? '');
        return;
      }

      if (msg.type === 'chat' && msg.text) {
        ws.send(JSON.stringify({ type: 'status', status: 'thinking' }));
        try {
          const result = await orchestrator.process(msg.text, config, wsSession);
          wsSession.push({ role: 'user', content: msg.text });
          wsSession.push({ role: 'assistant', content: result.response });
          ws.send(JSON.stringify({ type: 'response', ...result }));
        } catch (err) {
          ws.send(JSON.stringify({ type: 'error', error: err instanceof Error ? err.message : 'unknown' }));
        }
      }
    });

    ws.send(JSON.stringify({ type: 'connected', message: 'Odysseus v2 WebSocket' }));
  });

  // Heartbeat for stale connections
  const heartbeat = setInterval(() => {
    wss.clients.forEach((ws) => {
      if (ws.readyState === WebSocket.OPEN) {
        ws.ping();
      }
    });
  }, 30_000);

  wss.on('close', () => clearInterval(heartbeat));

  return {
    start: () =>
      new Promise<void>((resolve) => {
        server.listen(port, () => {
          resolve();
        });
      }),
    stop: () => {
      wss.close();
      server.close();
    },
    server,
  };
}

function handleWsCommand(ws: WebSocket, command: string) {
  switch (command) {
    case 'status':
      ws.send(JSON.stringify({ type: 'status_result', status: 'active' }));
      break;
    case 'health':
      ws.send(JSON.stringify({ type: 'health', status: 'ok' }));
      break;
    default:
      ws.send(JSON.stringify({ type: 'error', error: `unknown command: ${command}` }));
  }
}
