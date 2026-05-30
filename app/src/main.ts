import { spawn, ChildProcess } from 'node:child_process';
import { createRequire } from 'node:module';
import React from 'react';
import { render, Box, Text, useApp, useInput, useStdout } from 'ink';
import { loadConfig, type LLMConfig } from './llm.js';
import type { ChatMessage } from './llm-client.js';
import * as orchestrator from './frontal-orchestrator/index.js';
import { enrich, healthCheck, isBrainOnline } from './brain-bridge.js';
import { runWizard } from './wizard.js';
import { createServer } from './api/server.js';

const require = createRequire(import.meta.url);

// ── Brain launcher ────────────────────────────────────────────────

class BrainLauncher {
  private proc: ChildProcess | null = null;
  private ready = false;

  async start(projectRoot: string): Promise<boolean> {
    if (await healthCheck()) { this.ready = true; return true; }

    return new Promise((resolve) => {
      this.proc = spawn('mix', ['run', '--no-halt'], {
        cwd: `${projectRoot}/neural`,
        stdio: 'pipe',
        env: { ...process.env, MIX_ENV: 'dev' },
      });

      let attempts = 0;
      const poll = setInterval(async () => {
        attempts++;
        if (await healthCheck()) {
          clearInterval(poll); this.ready = true; resolve(true);
        } else if (attempts > 30) {
          clearInterval(poll); resolve(false);
        }
      }, 1000);
    });
  }

  stop() { this.proc?.kill('SIGTERM'); this.proc = null; }
  isReady() { return this.ready; }
}

// ── TUI ───────────────────────────────────────────────────────────

interface AppState {
  messages: Array<{ role: string; content: string }>;
  input: string;
  status: string;
  modelLabel: string;
  chatHistory: ChatMessage[];
}

function ChatUI({ initialState, config }: {
  initialState: AppState;
  config: LLMConfig;
}) {
  const { exit } = useApp();
  const { stdout } = useStdout();
  const [state, setStateRaw] = React.useState(initialState);

  const update = (partial: Partial<AppState>) => {
    setStateRaw((prev) => ({ ...prev, ...partial }));
  };

  useInput((ch, key) => {
    if (key.escape) { exit(); return; }
    if (key.return) {
      const text = state.input.trim();
      if (!text) return;
      if (text.startsWith('/')) handleCommand(text.slice(1), update);
      else handleInput(text, update);
      setStateRaw((prev) => ({ ...prev, input: '' }));
      return;
    }
    if (key.backspace || key.delete) {
      setStateRaw((prev) => ({ ...prev, input: prev.input.slice(0, -1) }));
      return;
    }
    setStateRaw((prev) => ({ ...prev, input: prev.input + ch }));
  });

  const termHeight = stdout?.rows ?? 24;
  const maxVisible = Math.max(5, termHeight - 5);

  return React.createElement(
    Box, { flexDirection: 'column', paddingX: 1 },
    // Header
    React.createElement(Box, { marginBottom: 1 },
      React.createElement(Text, { bold: true, color: 'cyan' }, 'Odysseus v2'),
      React.createElement(Text, { color: 'gray' }, ' — '),
      React.createElement(Text, { color: isBrainOnline() ? 'green' : 'yellow' },
        isBrainOnline() ? 'brain' : 'standalone'),
      React.createElement(Text, { color: 'gray' }, ' — '),
      React.createElement(Text, { color: 'magenta' }, state.modelLabel),
      state.status
        ? React.createElement(Text, { color: 'gray' }, ` — ${state.status}`)
        : null,
    ),
    // Messages
    React.createElement(Box, { flexDirection: 'column' },
      ...state.messages.slice(-maxVisible).map((msg, i) =>
        React.createElement(Box, { key: i },
          React.createElement(Text, {
            color: msg.role === 'system' ? 'gray' : msg.role === 'user' ? 'green' : 'blue',
          }, `${msg.role === 'user' ? '> ' : msg.role === 'assistant' ? '< ' : '# '}${msg.content}`),
        ),
      ),
    ),
    // Input
    React.createElement(Box, { borderStyle: 'single', borderColor: 'gray', paddingLeft: 1, marginTop: 1 },
      React.createElement(Text, { color: 'green' }, '> '),
      React.createElement(Text, null, state.input),
      React.createElement(Text, { backgroundColor: 'white' }, ' '),
    ),
  );

  async function handleInput(text: string, update: (s: Partial<AppState>) => void) {
    update({ status: 'thinking...' });
    addMsg('user', text);
    state.chatHistory.push({ role: 'user', content: text });

    try {
      const result = await orchestrator.process(text, config, state.chatHistory);
      addMsg('assistant', result.response);
      state.chatHistory.push({ role: 'assistant', content: result.response });
    } catch (err) {
      addMsg('assistant', `[error] ${err instanceof Error ? err.message : 'unknown'}`);
    }

    update({ messages: [...state.messages], chatHistory: [...state.chatHistory], status: '' });
  }

  function handleCommand(cmd: string, update: (s: Partial<AppState>) => void) {
    const command = cmd.split(' ')[0];
    switch (command) {
      case 'model':
        addMsg('system', `Left:  ${config.leftBrain.provider}/${config.leftBrain.model}\nRight: ${config.rightBrain.provider}/${config.rightBrain.model}`);
        break;
      case 'status':
        if (isBrainOnline()) {
          enrich('status').then(() => {
            addMsg('system', `Brain: online | Left: ${config.leftBrain.provider}/${config.leftBrain.model} | Right: ${config.rightBrain.provider}/${config.rightBrain.model}`);
            update({ messages: [...state.messages] });
          });
        } else {
          addMsg('system', `Brain: offline | Models: ${config.leftBrain.provider}/${config.leftBrain.model}`);
        }
        break;
      case 'clear':
        state.chatHistory = [];
        state.messages = [];
        update({ messages: [], chatHistory: [] });
        return;
      case 'help':
        addMsg('system', '/model /status /clear /init /help /exit');
        break;
      case 'init':
        exit();
        return;
      case 'exit':
        exit();
        return;
      default:
        addMsg('system', `Unknown: /${command}. Try /help`);
    }
    update({ messages: [...state.messages] });
  }

  function addMsg(role: string, content: string) {
    state.messages.push({ role, content });
  }
}

// ── Main ──────────────────────────────────────────────────────────

async function main() {
  const args = process.argv.slice(2);
  const apiMode = args.includes('--api');
  const portIdx = args.indexOf('--port');
  const apiPort = portIdx !== -1 ? parseInt(args[portIdx + 1], 10) : 3100;

  let config = loadConfig();
  if (!config) {
    config = await runWizard();
  }

  if (apiMode) {
    const api = createServer({ port: apiPort, config });
    await api.start();
    console.log(`Odysseus v2 API server on http://localhost:${apiPort}`);
    console.log(`WebSocket: ws://localhost:${apiPort}/ws`);
    return;
  }

  const projectRoot = findProjectRoot();
  const brain = new BrainLauncher();
  const leftLabel = `${config.leftBrain.provider}/${config.leftBrain.model}`;
  const rightLabel = config.rightBrain.provider !== config.leftBrain.provider
    ? `${config.rightBrain.provider}/${config.rightBrain.model}` : '';
  const modelLabel = rightLabel ? `${leftLabel} | ${rightLabel}` : leftLabel;

  const initialState: AppState = {
    messages: [],
    input: '',
    status: 'launching brain...',
    modelLabel,
    chatHistory: [],
  };

  render(React.createElement(ChatUI, { initialState, config }));

  addMsg(initialState, 'system', `Left brain:  ${leftLabel}`);
  if (rightLabel) addMsg(initialState, 'system', `Right brain: ${rightLabel}`);
  addMsg(initialState, 'system', 'Starting Elixir brain...');

  const connected = await brain.start(projectRoot);
  if (connected) {
    addMsg(initialState, 'system', 'Brain online');
  } else {
    addMsg(initialState, 'system', 'Standalone mode (brain offline)');
  }

  addMsg(initialState, 'assistant', "Hello! I'm Odysseus. Both hemispheres are ready.");

  function addMsg(state: AppState, role: string, content: string) {
    state.messages.push({ role, content });
  }
}

function findProjectRoot(): string {
  let dir = import.meta.dirname;
  const fs = require('fs') as typeof import('fs');
  const path = require('path') as typeof import('path');
  while (dir !== '/') {
    if (fs.existsSync(`${dir}/neural/mix.exs`) && fs.existsSync(`${dir}/core/Cargo.toml`)) return dir;
    dir = path.dirname(dir);
  }
  return import.meta.dirname;
}

main().catch((err) => { console.error('Fatal:', err); process.exit(1); });
