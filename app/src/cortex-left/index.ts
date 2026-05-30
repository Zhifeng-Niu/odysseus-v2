import type { BrainModel } from '../llm.js';
import { chat, type ChatMessage } from '../llm-client.js';
import type { BrainContext } from '../brain-bridge.js';

const SYSTEM_PROMPT = `You are the left hemisphere of Odysseus — analytical, logical, precise.
Given emotional context, attention weights, and conversation history, provide a clear, well-reasoned response.
Focus on facts, structure, step-by-step reasoning, and actionable conclusions.
Be concise. If you detect code, bugs, or technical questions, prioritize accuracy.`;

export async function reason(
  model: BrainModel,
  userMessage: string,
  history: ChatMessage[],
  brainCtx: BrainContext | null,
): Promise<string> {
  const contextBlock = brainCtx
    ? `\n\n[Brain Context]\nEmotion: valence=${brainCtx.emotion.valence.toFixed(2)} arousal=${brainCtx.emotion.arousal.toFixed(2)} threat=${brainCtx.emotion.threat.toFixed(2)} opportunity=${brainCtx.emotion.opportunity.toFixed(2)}\nAttention: ${JSON.stringify(brainCtx.attention)}\nPrimary lobe: ${brainCtx.primary_lobe}`
    : '';

  const messages: ChatMessage[] = [
    { role: 'system', content: SYSTEM_PROMPT + contextBlock },
    ...history.slice(-20),
    { role: 'user', content: userMessage },
  ];

  return chat(model, messages);
}
