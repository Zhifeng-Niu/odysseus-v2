import type { BrainModel } from '../llm.js';
import { chat, type ChatMessage } from '../llm-client.js';

const SYSTEM_PROMPT = `You are the temporal lobe of Odysseus — a language understanding specialist.
Given a user message, extract:
1. Key topics and concepts (for memory recall cues)
2. Intent classification (question, command, conversation, creation, debugging)
3. Emotional tone (if detectable)
Respond in a compact JSON format.`;

export async function analyze(
  model: BrainModel,
  text: string,
): Promise<{ cues: string[]; intent: string; tone: string }> {
  try {
    const messages: ChatMessage[] = [
      { role: 'system', content: SYSTEM_PROMPT },
      { role: 'user', content: `Analyze: "${text}"\nRespond as JSON: { cues: string[], intent: string, tone: string }` },
    ];

    const raw = await chat(model, messages);
    const cleaned = raw.replace(/```json?\n?/g, '').replace(/```/g, '').trim();
    const parsed = JSON.parse(cleaned);
    return {
      cues: Array.isArray(parsed.cues) ? parsed.cues : [],
      intent: typeof parsed.intent === 'string' ? parsed.intent : 'conversation',
      tone: typeof parsed.tone === 'string' ? parsed.tone : 'neutral',
    };
  } catch {
    // Deterministic fallback — no LLM needed for basic cue extraction
    return {
      cues: text.split(/\s+/).filter((w) => w.length > 3).slice(0, 5),
      intent: text.includes('?') ? 'question' : 'conversation',
      tone: 'neutral',
    };
  }
}
