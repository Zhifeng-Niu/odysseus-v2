import type { BrainModel } from './llm.js';

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}

export async function chat(model: BrainModel, messages: ChatMessage[]): Promise<string> {
  if (model.protocol === 'anthropic') {
    return chatAnthropic(model, messages);
  }
  return chatOpenAI(model, messages);
}

async function chatOpenAI(model: BrainModel, messages: ChatMessage[]): Promise<string> {
  const res = await fetch(`${model.baseUrl}/chat/completions`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${model.apiKey}`,
    },
    body: JSON.stringify({ model: model.model, messages, max_tokens: 2048, stream: false }),
    signal: AbortSignal.timeout(60000),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`LLM ${res.status}: ${body.slice(0, 200)}`);
  }

  const data = (await res.json()) as { choices: Array<{ message: { content: string } }> };
  return data.choices[0]?.message?.content ?? '[empty]';
}

async function chatAnthropic(model: BrainModel, messages: ChatMessage[]): Promise<string> {
  const systemMsg = messages.find((m) => m.role === 'system')?.content;
  const nonSystem = messages.filter((m) => m.role !== 'system');

  const res = await fetch(`${model.baseUrl}/v1/messages`, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': model.apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: model.model,
      max_tokens: 2048,
      system: systemMsg,
      messages: nonSystem,
    }),
    signal: AbortSignal.timeout(60000),
  });

  if (!res.ok) {
    const body = await res.text();
    throw new Error(`LLM ${res.status}: ${body.slice(0, 200)}`);
  }

  const data = (await res.json()) as { content: Array<{ type: string; text: string }> };
  return data.content[0]?.text ?? '[empty]';
}
