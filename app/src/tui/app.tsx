import React from 'react';
import { render, Box, Text, useApp, useInput } from 'ink';

interface TUIConfig {
  onInput: (text: string) => void;
  onCommand: (cmd: string) => void;
}

interface TUIMessage {
  key: number;
  role: string;
  content: string;
}

export class OdysseusTUI {
  private config: TUIConfig;
  private messages: TUIMessage[] = [];
  private rerender: (() => void) | null = null;
  private keyCounter = 0;

  constructor(config: TUIConfig) {
    this.config = config;
  }

  async render(): Promise<void> {
    const App = this.createApp();
    const { rerender } = render(React.createElement(App));
    this.rerender = rerender as () => void;
  }

  addMessage(role: string, content: string): void {
    this.messages.push({ key: this.keyCounter++, role, content });
    this.rerender?.();
  }

  cleanup(): void {
    // ink handles cleanup on unmount
  }

  private createApp() {
    const config = this.config;
    const getMessages = () => this.messages;

    const App: React.FC = () => {
      const { exit } = useApp();
      const [input, setInput] = React.useState('');
      const messages = getMessages();

      useInput((ch, key) => {
        if (key.escape) {
          exit();
          return;
        }
        if (key.return) {
          const text = input.trim();
          if (!text) return;
          if (text.startsWith('/')) {
            config.onCommand(text.slice(1));
          } else {
            config.onInput(text);
          }
          setInput('');
          return;
        }
        if (key.backspace || key.delete) {
          setInput(prev => prev.slice(0, -1));
          return;
        }
        setInput(prev => prev + ch);
      });

      return React.createElement(
        Box,
        { flexDirection: 'column', padding: 1 },
        // Header
        React.createElement(
          Box,
          { marginBottom: 1 },
          React.createElement(Text, { bold: true, color: 'cyan' }, 'Odysseus v2'),
          React.createElement(Text, { color: 'gray' }, ' — brain-inspired agent runtime'),
        ),
        // Messages
        React.createElement(
          Box,
          { flexDirection: 'column', marginBottom: 1 },
          ...messages.slice(-20).map((msg) =>
            React.createElement(
              Box,
              { key: msg.key },
              React.createElement(
                Text,
                { color: msg.role === 'system' ? 'gray' : msg.role === 'user' ? 'green' : 'blue' },
                `${msg.role === 'user' ? '> ' : msg.role === 'assistant' ? '< ' : '# '}${msg.content}`,
              ),
            ),
          ),
        ),
        // Input
        React.createElement(
          Box,
          { borderStyle: 'single', borderColor: 'gray', paddingLeft: 1 },
          React.createElement(Text, { color: 'green' }, '> '),
          React.createElement(Text, null, input),
          React.createElement(Text, { backgroundColor: 'white' }, ' '),
        ),
      );
    };

    return App;
  }
}
