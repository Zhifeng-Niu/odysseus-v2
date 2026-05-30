import type { LLMConfig } from '../llm.js';
import type { ChatMessage } from '../llm-client.js';
import { enrich, sendToBrain } from '../brain-bridge.js';
import * as cortexLeft from '../cortex-left/index.js';
import * as cortexRight from '../cortex-right/index.js';

export interface OrchestratorResult {
  response: string;
  leftBrain?: string;
  rightBrain?: string;
  brainContext: boolean;
  primaryLobe: string;
}

export async function process(
  text: string,
  config: LLMConfig,
  history: ChatMessage[],
): Promise<OrchestratorResult> {
  // Step 1: Get brain enrichment (emotion, features, attention)
  const brainCtx = await enrich(text);
  const hasBrain = brainCtx !== null;

  // Step 2: Send to brain for memory/emotional processing
  if (hasBrain) {
    await sendToBrain(text);
  }

  // Step 3: Parallel left + right brain reasoning
  const sameModel = config.leftBrain.apiKey === config.rightBrain.apiKey
    && config.leftBrain.model === config.rightBrain.model;

  let leftResult: string;
  let rightResult: string;

  if (sameModel) {
    // Same model — run sequentially to avoid rate limit
    leftResult = await cortexLeft.reason(config.leftBrain, text, history, brainCtx);
    rightResult = await cortexRight.reason(config.rightBrain, text, history, brainCtx);
  } else {
    // Different models — run in parallel
    [leftResult, rightResult] = await Promise.all([
      cortexLeft.reason(config.leftBrain, text, history, brainCtx),
      cortexRight.reason(config.rightBrain, text, history, brainCtx),
    ]);
  }

  // Step 4: Merge — if right brain is short, append as supplement
  const merged = mergeResponses(leftResult, rightResult);

  return {
    response: merged,
    leftBrain: leftResult,
    rightBrain: rightResult,
    brainContext: hasBrain,
    primaryLobe: brainCtx?.primary_lobe ?? 'standalone',
  };
}

function mergeResponses(left: string, right: string): string {
  // If right brain only adds a little, append it
  const rightTrimmed = right.trim();
  if (!rightTrimmed || rightTrimmed === left.trim()) return left;

  // If right brain is very short (1-3 sentences), append as insight
  const rightLines = rightTrimmed.split('\n').filter((l) => l.trim());
  if (rightLines.length <= 3) {
    return `${left}\n\n💡 ${rightTrimmed}`;
  }

  // Otherwise return left brain as primary
  return left;
}
