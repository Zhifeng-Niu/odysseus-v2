import type { LLMConfig } from '../llm.js';
import type { ChatMessage } from '../llm-client.js';
import { enrich } from '../brain-bridge.js';
import * as cortex from '../cortex-left/index.js';

export interface OrchestratorResult {
  response: string;
  brainContext: boolean;
  primaryLobe: string;
}

export async function process(
  text: string,
  config: LLMConfig,
  history: ChatMessage[],
): Promise<OrchestratorResult> {
  const brainCtx = await enrich(text);

  const response = await cortex.reason(
    config.leftBrain, text, history, brainCtx,
  );

  return {
    response,
    brainContext: brainCtx !== null,
    primaryLobe: brainCtx?.primary_lobe ?? 'direct',
  };
}
