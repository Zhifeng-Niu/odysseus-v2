// Cortex: 4-lobe processing with LLM reasoning
// Frontal (planning) | Parietal (integration) | Temporal (language) | Occipital (visualization)

export type LobeRole = 'frontal' | 'parietal' | 'temporal' | 'occipital';

export interface CortexConfig {
  model: string;
  maxTokens: number;
  temperature: number;
}
