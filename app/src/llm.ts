import { readFileSync, writeFileSync, existsSync, mkdirSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

export type ProviderName =
  | 'openai' | 'anthropic' | 'openrouter' | 'gemini'
  | 'deepseek' | 'minimax' | 'glm' | 'qwen'
  | 'moonshot' | 'yi' | 'baichuan' | 'zhipu';

export type Protocol = 'openai' | 'anthropic';

export interface BrainModel {
  provider: ProviderName;
  model: string;
  apiKey: string;
  baseUrl: string;
  protocol: Protocol;
}

export interface LLMConfig {
  leftBrain: BrainModel;
  rightBrain: BrainModel;
  systemPrompt: string;
}

const CONFIG_DIR = join(homedir(), '.odysseus-v2');
const CONFIG_PATH = join(CONFIG_DIR, 'config.json');

export const SYSTEM_PROMPT_LEFT = `You are the left hemisphere of Odysseus — analytical, logical, precise. Given emotional context and conversation history, provide a clear, well-reasoned response. Focus on facts, structure, and actionable steps. Be concise.`;

export const SYSTEM_PROMPT_RIGHT = `You are the right hemisphere of Odysseus — creative, intuitive, empathetic. Given the same context, provide an alternative perspective. Focus on patterns, connections, emotional nuance, and creative possibilities. Be warm and insightful.`;

const PROVIDER_DEFAULTS: Record<string, { baseUrl: string; model: string; protocol: Protocol }> = {
  openai:     { baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o', protocol: 'openai' },
  anthropic:  { baseUrl: 'https://api.anthropic.com', model: 'claude-sonnet-4-20250514', protocol: 'anthropic' },
  openrouter: { baseUrl: 'https://openrouter.ai/api/v1', model: 'anthropic/claude-sonnet-4-20250514', protocol: 'openai' },
  gemini:     { baseUrl: 'https://generativelanguage.googleapis.com/v1beta', model: 'gemini-2.5-pro', protocol: 'openai' },
  deepseek:   { baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-chat', protocol: 'openai' },
  minimax:    { baseUrl: 'https://api.minimax.chat/v1', model: 'MiniMax-Text-01', protocol: 'openai' },
  glm:        { baseUrl: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4-plus', protocol: 'openai' },
  qwen:       { baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-max', protocol: 'openai' },
  moonshot:   { baseUrl: 'https://api.moonshot.cn/v1', model: 'moonshot-v1-128k', protocol: 'openai' },
  yi:         { baseUrl: 'https://api.lingyiwanwu.com/v1', model: 'yi-lightning', protocol: 'openai' },
  baichuan:   { baseUrl: 'https://api.baichuan-ai.com/v1', model: 'Baichuan4', protocol: 'openai' },
  zhipu:      { baseUrl: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4-plus', protocol: 'openai' },
};

export const PROVIDERS = Object.keys(PROVIDER_DEFAULTS) as ProviderName[];

export function getDefaults(provider: string) {
  return PROVIDER_DEFAULTS[provider] ?? { baseUrl: '', model: 'gpt-4o', protocol: 'openai' as Protocol };
}

export function loadConfig(): LLMConfig | null {
  const envKey = process.env.ODY_API_KEY || process.env.ODYSSEUS_API_KEY;
  const envProvider = process.env.ODY_PROVIDER || process.env.ODYSSEUS_LLM_PROVIDER || 'openai';
  const envModel = process.env.ODY_MODEL || process.env.ODYSSEUS_MODEL;
  const envBaseUrl = process.env.ODY_BASE_URL || process.env.ODYSSEUS_BASE_URL;

  if (envKey) {
    const d = getDefaults(envProvider);
    const brain: BrainModel = {
      provider: envProvider as ProviderName,
      model: envModel ?? d.model,
      apiKey: envKey,
      baseUrl: envBaseUrl ?? d.baseUrl,
      protocol: d.protocol,
    };
    return { leftBrain: brain, rightBrain: brain, systemPrompt: '' };
  }

  if (existsSync(CONFIG_PATH)) {
    try {
      const raw = JSON.parse(readFileSync(CONFIG_PATH, 'utf-8'));

      // Legacy format: { provider, apiKey, model, ... } → use for both brains
      if (raw.provider && raw.apiKey && !raw.leftBrain) {
        const d = getDefaults(raw.provider);
        const brain: BrainModel = {
          provider: raw.provider,
          model: raw.model ?? d.model,
          apiKey: raw.apiKey,
          baseUrl: raw.baseUrl ?? d.baseUrl,
          protocol: raw.protocol ?? d.protocol,
        };
        return { leftBrain: brain, rightBrain: brain, systemPrompt: raw.systemPrompt ?? '' };
      }

      // New format: { leftBrain, rightBrain, ... }
      const resolve = (b: Partial<BrainModel> & { provider: ProviderName }): BrainModel => {
        const d = getDefaults(b.provider);
        return {
          provider: b.provider,
          model: b.model ?? d.model,
          apiKey: b.apiKey ?? raw.leftBrain?.apiKey ?? '',
          baseUrl: b.baseUrl ?? d.baseUrl,
          protocol: b.protocol ?? d.protocol,
        };
      };

      return {
        leftBrain: resolve(raw.leftBrain),
        rightBrain: raw.rightBrain ? resolve(raw.rightBrain) : resolve(raw.leftBrain),
        systemPrompt: raw.systemPrompt ?? '',
      };
    } catch {
      return null;
    }
  }

  return null;
}

export function saveConfig(config: LLMConfig): void {
  if (!existsSync(CONFIG_DIR)) mkdirSync(CONFIG_DIR, { recursive: true });
  writeFileSync(CONFIG_PATH, JSON.stringify(config, null, 2));
}
