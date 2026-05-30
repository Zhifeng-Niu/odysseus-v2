import React from 'react';
import { render, Box, Text, useApp, useInput } from 'ink';
import { PROVIDERS, getDefaults, saveConfig, type LLMConfig, type BrainModel, type ProviderName } from './llm.js';

type Step = 'welcome' | 'left-provider' | 'left-key' | 'left-model' | 'left-url'
  | 'right-separate' | 'right-provider' | 'right-key' | 'right-model' | 'right-url' | 'done';

export function runWizard(): Promise<LLMConfig> {
  return new Promise((resolve) => {
    let resolved = false;
    const instance = render(
      React.createElement(WizardApp, {
        onDone: (config: LLMConfig) => { resolved = true; resolve(config); },
      }),
    );
    instance.waitUntilExit().then(() => {
      if (!resolved) process.exit(0);
    });
  });
}

function WizardApp({ onDone }: { onDone: (c: LLMConfig) => void }) {
  const { exit } = useApp();
  const [step, setStep] = React.useState<Step>('welcome');
  const [history, setHistory] = React.useState<Step[]>([]);
  const [cursor, setCursor] = React.useState(0);
  const [input, setInput] = React.useState('');
  const [leftProvider, setLeftProvider] = React.useState<ProviderName | null>(null);
  const [leftKey, setLeftKey] = React.useState('');
  const [leftModel, setLeftModel] = React.useState('');
  const [leftUrl, setLeftUrl] = React.useState('');
  const [rightProvider, setRightProvider] = React.useState<ProviderName | null>(null);
  const [rightKey, setRightKey] = React.useState('');
  const [rightModel, setRightModel] = React.useState('');
  const [rightUrl, setRightUrl] = React.useState('');
  const [separateBrains, setSeparateBrains] = React.useState(false);

  const go = (next: Step) => {
    setHistory((prev) => [...prev, step]);
    setStep(next);
    setInput('');
    setCursor(0);
  };

  const back = () => {
    if (history.length > 0) {
      const prev = [...history];
      const last = prev.pop()!;
      setHistory(prev);
      setStep(last);
      setInput('');
      setCursor(0);
    }
  };

  const finish = () => {
    const lp = leftProvider!;
    const ld = getDefaults(lp);
    const left: BrainModel = {
      provider: lp,
      model: leftModel || ld.model,
      apiKey: leftKey,
      baseUrl: leftUrl || ld.baseUrl,
      protocol: ld.protocol,
    };

    let right: BrainModel;
    if (separateBrains && rightProvider) {
      const rd = getDefaults(rightProvider);
      right = {
        provider: rightProvider,
        model: rightModel || rd.model,
        apiKey: rightKey || leftKey,
        baseUrl: rightUrl || rd.baseUrl,
        protocol: rd.protocol,
      };
    } else {
      right = left;
    }

    const config: LLMConfig = { leftBrain: left, rightBrain: right, systemPrompt: '' };
    saveConfig(config);
    setStep('done');
    onDone(config);
  };

  useInput((ch, key) => {
    if (key.escape) {
      if (step === 'welcome') { exit(); return; }
      back();
      return;
    }

    if (step === 'welcome' || step === 'done') {
      if (key.return) {
        if (step === 'welcome') go('left-provider');
        else exit();
      }
      return;
    }

    // Selection screens
    if (step === 'left-provider' || step === 'right-provider' || step === 'right-separate') {
      const itemCount = step === 'right-separate' ? 2 : PROVIDERS.length;
      if (key.upArrow) { setCursor(Math.max(0, cursor - 1)); return; }
      if (key.downArrow) { setCursor(Math.min(itemCount - 1, cursor + 1)); return; }
      if (key.return) {
        if (step === 'left-provider') {
          setLeftProvider(PROVIDERS[cursor]);
          go('left-key');
        } else if (step === 'right-separate') {
          const sep = cursor === 1;
          setSeparateBrains(sep);
          if (sep) go('right-provider'); else finish();
        } else {
          setRightProvider(PROVIDERS[cursor]);
          go('right-key');
        }
      }
      return;
    }

    // Text input screens
    if (key.return) {
      const val = input.trim();
      if (step === 'left-key') { if (!val) return; setLeftKey(val); go('left-model'); }
      else if (step === 'left-model') { setLeftModel(val); go('left-url'); }
      else if (step === 'left-url') { setLeftUrl(val); go('right-separate'); }
      else if (step === 'right-key') { setRightKey(val); go('right-model'); }
      else if (step === 'right-model') { setRightModel(val); go('right-url'); }
      else if (step === 'right-url') { setRightUrl(val); finish(); }
      return;
    }

    if (key.backspace || key.delete) { setInput(input.slice(0, -1)); return; }
    setInput(input + ch);
  });

  return React.createElement(
    Box, { flexDirection: 'column', paddingX: 2 },
    React.createElement(Box, { marginBottom: 1 },
      React.createElement(Text, { bold: true, color: 'cyan' }, 'Odysseus v2'),
      React.createElement(Text, { color: 'gray' }, ' — Setup Wizard'),
    ),
    renderContent(),
  );

  function renderContent(): React.ReactElement {
    switch (step) {
      case 'welcome':
        return React.createElement(Box, { flexDirection: 'column' },
          React.createElement(Text, null, ''),
          React.createElement(Text, { bold: true }, 'Welcome to Odysseus v2'),
          React.createElement(Text, null, ''),
          React.createElement(Text, { color: 'gray' }, 'Configure left brain (analytical) and right brain (creative) models.'),
          React.createElement(Text, null, ''),
          React.createElement(Text, { color: 'green' }, 'Press Enter to start'),
        );

      case 'left-provider':
        return React.createElement(Box, { flexDirection: 'column' },
          React.createElement(Text, { bold: true }, 'Left Brain (Analytical) — Select Provider'),
          React.createElement(Text, { color: 'gray' }, '↑↓ navigate · Enter select · Esc back'),
          React.createElement(Text, null, ''),
          ...PROVIDERS.map((p, i) =>
            React.createElement(Text, { key: p, color: i === cursor ? 'cyan' : 'gray' },
              `${i === cursor ? '❯ ' : '  '}${p}`),
          ),
        );

      case 'right-provider':
        return React.createElement(Box, { flexDirection: 'column' },
          React.createElement(Text, { bold: true }, 'Right Brain (Creative) — Select Provider'),
          React.createElement(Text, { color: 'gray' }, '↑↓ navigate · Enter select · Esc back'),
          React.createElement(Text, null, ''),
          ...PROVIDERS.map((p, i) =>
            React.createElement(Text, { key: p, color: i === cursor ? 'cyan' : 'gray' },
              `${i === cursor ? '❯ ' : '  '}${p}`),
          ),
        );

      case 'right-separate':
        return React.createElement(Box, { flexDirection: 'column' },
          React.createElement(Text, { bold: true }, 'Right Brain Configuration'),
          React.createElement(Text, null, ''),
          React.createElement(Text, null, 'Use a different model for the right brain?'),
          React.createElement(Text, { color: cursor === 0 ? 'cyan' : 'gray' },
            `${cursor === 0 ? '❯ ' : '  '}No — same model for both brains`),
          React.createElement(Text, { color: cursor === 1 ? 'cyan' : 'gray' },
            `${cursor === 1 ? '❯ ' : '  '}Yes — configure right brain separately`),
        );

      case 'left-key':
        return React.createElement(Box, { flexDirection: 'column' },
          React.createElement(Text, { bold: true }, `Left Brain — ${leftProvider}`),
          React.createElement(Text, null, ''),
          React.createElement(Text, null, 'API Key:'),
          React.createElement(Text, { color: 'green' }, input || '(paste your key)'),
        );

      case 'right-key':
        return React.createElement(Box, { flexDirection: 'column' },
          React.createElement(Text, { bold: true }, `Right Brain — ${rightProvider}`),
          React.createElement(Text, null, ''),
          React.createElement(Text, null, 'API Key (Enter to share left brain key):'),
          React.createElement(Text, { color: 'green' }, input || '(press Enter to use same key)'),
        );

      case 'left-model': {
        const d = leftProvider ? getDefaults(leftProvider) : { model: '' };
        return React.createElement(Box, { flexDirection: 'column' },
          React.createElement(Text, { bold: true }, 'Left Brain — Model'),
          React.createElement(Text, { color: 'gray' }, `Default: ${d.model}`),
          React.createElement(Text, null, ''),
          React.createElement(Text, null, `Model [${d.model}]:`),
          React.createElement(Text, { color: 'green' }, input || '(Enter for default)'),
        );
      }

      case 'right-model': {
        const d = rightProvider ? getDefaults(rightProvider) : { model: '' };
        return React.createElement(Box, { flexDirection: 'column' },
          React.createElement(Text, { bold: true }, 'Right Brain — Model'),
          React.createElement(Text, { color: 'gray' }, `Default: ${d.model}`),
          React.createElement(Text, null, ''),
          React.createElement(Text, null, `Model [${d.model}]:`),
          React.createElement(Text, { color: 'green' }, input || '(Enter for default)'),
        );
      }

      case 'left-url': {
        const d = leftProvider ? getDefaults(leftProvider) : { baseUrl: '' };
        return React.createElement(Box, { flexDirection: 'column' },
          React.createElement(Text, { bold: true }, 'Left Brain — Base URL'),
          React.createElement(Text, { color: 'gray' }, `Default: ${d.baseUrl}`),
          React.createElement(Text, null, ''),
          React.createElement(Text, null, `URL [${d.baseUrl}]:`),
          React.createElement(Text, { color: 'green' }, input || '(Enter for default)'),
        );
      }

      case 'right-url': {
        const d = rightProvider ? getDefaults(rightProvider) : { baseUrl: '' };
        return React.createElement(Box, { flexDirection: 'column' },
          React.createElement(Text, { bold: true }, 'Right Brain — Base URL'),
          React.createElement(Text, { color: 'gray' }, `Default: ${d.baseUrl}`),
          React.createElement(Text, null, ''),
          React.createElement(Text, null, `URL [${d.baseUrl}]:`),
          React.createElement(Text, { color: 'green' }, input || '(Enter for default)'),
        );
      }

      case 'done':
        return React.createElement(Box, { flexDirection: 'column' },
          React.createElement(Text, { bold: true, color: 'green' }, 'Configuration saved!'),
          React.createElement(Text, null, ''),
          React.createElement(Text, null, `Left brain:  ${leftProvider}/${leftModel || getDefaults(leftProvider!).model}`),
          React.createElement(Text, null, `Right brain: ${separateBrains ? `${rightProvider}/${rightModel || getDefaults(rightProvider!).model}` : '(same as left)'}`),
          React.createElement(Text, null, ''),
          React.createElement(Text, { color: 'gray' }, 'Saved to ~/.odysseus-v2/config.json'),
          React.createElement(Text, { color: 'green' }, 'Press Enter to start'),
        );
    }
  }
}
