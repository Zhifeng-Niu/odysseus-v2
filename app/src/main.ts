import { createRequire } from 'node:module';
import React from 'react';
import { render, Box, Text, useApp, useInput, useStdout } from 'ink';
import { loadConfig, type LLMConfig } from './llm.js';
import type { ChatMessage } from './llm-client.js';
import * as orchestrator from './frontal-orchestrator/index.js';
import { healthCheck, isBrainOnline } from './brain-bridge.js';
import { runWizard, WizardApp } from './wizard.js';
import { createServer } from './api/server.js';

const require = createRequire(import.meta.url);

// ── App Shell ─────────────────────────────────────────────────────

function AppShell({ config, brainReady }: {
  config: LLMConfig;
  brainReady: boolean;
}) {
  const [mode, setMode] = React.useState<'chat' | 'wizard'>('chat');
  const [currentConfig, setCurrentConfig] = React.useState(config);
  const [chatKey, setChatKey] = React.useState(0);

  if (mode === 'wizard') {
    return React.createElement(WizardApp, {
      onDone: (c: LLMConfig) => {
        setCurrentConfig(c);
        setChatKey((k) => k + 1);
        setMode('chat');
      },
      onClose: () => setMode('chat'),
    });
  }

  const leftLabel = `${currentConfig.leftBrain.provider}/${currentConfig.leftBrain.model}`;

  return React.createElement(ChatUI, {
    key: chatKey,
    config: currentConfig,
    brainReady,
    modelLabel: leftLabel,
    onOpenConfig: () => setMode('wizard'),
  });
}

// ── TUI ───────────────────────────────────────────────────────────

interface AppState {
  messages: Array<{ role: string; content: string }>;
  input: string;
  status: string;
  modelLabel: string;
  chatHistory: ChatMessage[];
}

function ChatUI({ config, brainReady, modelLabel, onOpenConfig }: {
  config: LLMConfig;
  brainReady: boolean;
  modelLabel: string;
  onOpenConfig: () => void;
}) {
  const { exit } = useApp();
  const { stdout } = useStdout();
  const [state, setStateRaw] = React.useState<AppState>({
    messages: [],
    input: '',
    status: '',
    modelLabel,
    chatHistory: [],
  });

  const update = (partial: Partial<AppState>) => {
    setStateRaw((prev) => ({ ...prev, ...partial }));
  };

  // Boot messages
  React.useEffect(() => {
    const msgs: Array<{ role: string; content: string }> = [];
    msgs.push({ role: 'system', content: `Model: ${modelLabel}` });
    msgs.push({ role: 'system', content: brainReady ? 'Brain online' : 'Brain starting...' });
    msgs.push({ role: 'assistant', content: "Hello! I'm Odysseus." });
    update({ messages: msgs });
  }, []);

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
        isBrainOnline() ? 'brain' : 'connecting'),
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
        addMsg('system', `Model: ${config.leftBrain.provider}/${config.leftBrain.model}`);
        break;
      case 'clear':
        state.chatHistory = [];
        state.messages = [];
        update({ messages: [], chatHistory: [] });
        return;
      case 'help':
        addMsg('system', '/model /config /clear /help /exit');
        break;
      case 'config':
        onOpenConfig();
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

  // Wait for brain to be ready
  console.log('Connecting to brain...');
  const brainReady = await waitForBrain();
  if (!brainReady) {
    console.error('Brain unavailable. Start Elixir brain first:');
    console.error('  cd neural && mix run --no-halt');
    process.exit(1);
  }

  render(React.createElement(AppShell, { config, brainReady }));
}

async function waitForBrain(attempts = 10): Promise<boolean> {
  for (let i = 0; i < attempts; i++) {
    if (await healthCheck()) return true;
    await new Promise((r) => setTimeout(r, 1000));
  }
  return false;
}

main().catch((err) => { console.error('Fatal:', err); process.exit(1); });
