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

export async function enrich(text: string, intensity = 0.5): Promise<BrainContext | null> {
  try {
    const res = await fetch(`${BRAIN_URL}/enrich`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: text, intensity }),
      signal: AbortSignal.timeout(3000),
    });
    if (!res.ok) return null;
    brainOnline = true;
    return (await res.json()) as BrainContext;
  } catch {
    return null;
  }
}

export async function sendToBrain(text: string, intensity = 0.5): Promise<boolean> {
  try {
    const res = await fetch(`${BRAIN_URL}/chat`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ message: text, source: 'cli', intensity }),
      signal: AbortSignal.timeout(3000),
    });
    brainOnline = res.ok;
    return res.ok;
  } catch {
    return false;
  }
}

export async function healthCheck(): Promise<boolean> {
  try {
    const res = await fetch(`${BRAIN_URL}/health`, { signal: AbortSignal.timeout(1500) });
    brainOnline = res.ok;
    return res.ok;
  } catch {
    brainOnline = false;
    return false;
  }
}

export function isBrainOnline(): boolean {
  return brainOnline;
}
