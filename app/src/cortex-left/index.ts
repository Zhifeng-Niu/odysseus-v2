import type { BrainModel } from '../llm.js';
import { chat, type ChatMessage } from '../llm-client.js';
import type { BrainContext } from '../brain-bridge.js';

const SYSTEM_PROMPT = `You are Odysseus, an autonomous agent with a brain-inspired architecture.
You receive signals enriched by emotional processing, memory, and attention allocation.
Respond as a unified intelligence — balance analytical precision with intuitive depth.
Be concise. Adapt your tone naturally to the context.`;

export async function reason(
  model: BrainModel,
  userMessage: string,
  history: ChatMessage[],
  brainCtx: BrainContext | null,
): Promise<string> {
  const contextBlock = brainCtx
    ? `\n\n[Brain State]\nEmotion: valence=${brainCtx.emotion.valence.toFixed(2)} arousal=${brainCtx.emotion.arousal.toFixed(2)} threat=${brainCtx.emotion.threat.toFixed(2)} opportunity=${brainCtx.emotion.opportunity.toFixed(2)}\nAttention: ${JSON.stringify(brainCtx.attention)}\nActive lobe: ${brainCtx.primary_lobe}\nFeatures: words=${brainCtx.features.word_count} question=${brainCtx.features.has_question} code=${brainCtx.features.has_code}`
    : '';

  const messages: ChatMessage[] = [
    { role: 'system', content: SYSTEM_PROMPT + contextBlock },
    ...history.slice(-20),
    { role: 'user', content: userMessage },
  ];

  return chat(model, messages);
}
