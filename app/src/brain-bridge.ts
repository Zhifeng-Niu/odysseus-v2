const BRAIN_URL = process.env.ODYSSEUS_BRAIN_URL || 'http://localhost:4001';

export interface BrainContext {
  emotion: {
    valence: number;
    arousal: number;
    urgency: number;
    threat: number;
    opportunity: number;
  };
  features: {
    length: number;
    word_count: number;
    has_question: boolean;
    has_code: boolean;
  };
  attention: Record<string, number>;
  primary_lobe: string;
  intensity: number;
}

let brainOnline = false;

export async function enrich(text: string, intensity = 0.5): Promise<BrainContext> {
  if (!brainOnline) {
    await probeBrain();
    if (!brainOnline) {
      throw new Error('Brain unavailable — start Elixir brain first (mix run --no-halt)');
    }
  }

  try {
    const res = await fetch(`${BRAIN_URL}/enrich`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: text, intensity }),
      signal: AbortSignal.timeout(3000),
    });
    if (!res.ok) throw new Error(`Brain /enrich returned ${res.status}`);
    return (await res.json()) as BrainContext;
  } catch (err) {
    brainOnline = false;
    throw err;
  }
}

export async function healthCheck(): Promise<boolean> {
  return probeBrain();
}

export function isBrainOnline(): boolean {
  return brainOnline;
}

async function probeBrain(): Promise<boolean> {
  try {
    const res = await fetch(`${BRAIN_URL}/health`, { signal: AbortSignal.timeout(1500) });
    brainOnline = res.ok;
    return brainOnline;
  } catch {
    brainOnline = false;
    return false;
  }
}
