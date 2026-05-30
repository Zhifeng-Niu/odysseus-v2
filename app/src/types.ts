export type SensorySource = 'cli' | 'webhook' | 'telegram' | 'code' | 'socket';
export type SensoryModality = 'text' | 'command' | 'event' | 'error';
export type LobeType = 'frontal' | 'parietal' | 'temporal' | 'occipital';
export type Priority = 'low' | 'normal' | 'high' | 'critical';

export interface SensorySignal {
  source: SensorySource;
  modality: SensoryModality;
  raw: string;
  intensity: number;
  timestamp: number;
}

export interface RoutedSignal {
  target: LobeType;
  content: string;
  modality: string;
  attentionWeight: number;
  priority: Priority;
  timestamp: number;
}

export interface EmotionalTag {
  valence: number;
  arousal: number;
  urgency: number;
  threat: number;
  opportunity: number;
  source: string;
}

export interface TaggedExperience {
  content: string;
  emotionalWeight: number;
  valence: number;
  arousal: number;
  context: string[];
  timestamp: number;
}

export interface ActionCandidate {
  action: string;
  expectedReward: number;
  confidence: number;
  riskLevel: number;
  reasoning: string;
  context: string[];
}

export interface MotorPlan {
  action: string;
  predictedOutcome: string;
  timelineMs: number;
  expectedStates: Array<{ step: number; description: string; confidence: number }>;
}

export interface ActivationSignal {
  neuronId: string;
  activationLevel: number;
  trigger: string;
  spreadTo: Array<{ targetId: string; weight: number }>;
}
