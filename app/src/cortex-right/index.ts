import type { BrainModel } from '../llm.js';
import { chat, type ChatMessage } from '../llm-client.js';
import type { BrainContext } from '../brain-bridge.js';

const SYSTEM_PROMPT = `You are the creative subsystem of Odysseus.
Given emotional context and conversation history, provide an alternative perspective.
Focus on patterns, emotional nuance, creative possibilities, and big-picture connections.
Be warm and insightful. Keep it concise.`;

export async function reason(
  model: BrainModel,
  userMessage: string,
  history: ChatMessage[],
  brainCtx: BrainContext | null,
): Promise<string> {
  const contextBlock = brainCtx
    ? `\n\n[Brain State]\nEmotion: valence=${brainCtx.emotion.valence.toFixed(2)} arousal=${brainCtx.emotion.arousal.toFixed(2)}\nUser seems ${brainCtx.emotion.valence > 0.2 ? 'positive' : brainCtx.emotion.valence < -0.2 ? 'concerned' : 'neutral'}${brainCtx.features.has_question ? '. They asked a question.' : ''}${brainCtx.features.has_code ? '. They shared code.' : ''}`
    : '';

  const messages: ChatMessage[] = [
    { role: 'system', content: SYSTEM_PROMPT + contextBlock },
    ...history.slice(-10),
    { role: 'user', content: userMessage },
  ];

  return chat(model, messages);
}
