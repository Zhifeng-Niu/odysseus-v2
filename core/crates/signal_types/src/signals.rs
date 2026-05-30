use serde::{Deserialize, Serialize};

// ─── Layer 1: Brainstem → Thalamus ────────────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifUnitEnum))]
pub enum SensorySource {
    Cli,
    Webhook,
    Telegram,
    Code,
    Socket,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifUnitEnum))]
pub enum SensoryModality {
    Text,
    Command,
    Event,
    Error,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifStruct))]
#[cfg_attr(feature = "nif", module = "Odysseus.Signals.SensorySignal")]
pub struct SensorySignal {
    pub source: SensorySource,
    pub modality: SensoryModality,
    pub raw: String,
    pub intensity: f64,
    pub timestamp: u64,
}

// ─── Layer 2: Thalamus → Cortex / Amygdala ───────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifUnitEnum))]
pub enum LobeType {
    Frontal,
    Parietal,
    Temporal,
    Occipital,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifUnitEnum))]
pub enum Priority {
    Low,
    Normal,
    High,
    Critical,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifStruct))]
#[cfg_attr(feature = "nif", module = "Odysseus.Signals.RoutedSignal")]
pub struct RoutedSignal {
    pub target: LobeType,
    pub content: String,
    pub modality: String,
    pub attention_weight: f64,
    pub priority: Priority,
    pub timestamp: u64,
}

// ─── Fast Path: Thalamus → Amygdala (no LLM) ────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifStruct))]
#[cfg_attr(feature = "nif", module = "Odysseus.Signals.EmotionalTag")]
pub struct EmotionalTag {
    pub valence: f64,
    pub arousal: f64,
    pub urgency: f64,
    pub threat: f64,
    pub opportunity: f64,
    pub source: String,
}

impl EmotionalTag {
    pub fn neutral() -> Self {
        Self {
            valence: 0.0,
            arousal: 0.0,
            urgency: 0.0,
            threat: 0.0,
            opportunity: 0.0,
            source: String::new(),
        }
    }

    pub fn is_critical(&self) -> bool {
        self.threat > 0.8 || self.urgency > 0.8
    }
}

// ─── Layer 3: Amygdala + Cortex → Hippocampus ────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifStruct))]
#[cfg_attr(feature = "nif", module = "Odysseus.Signals.TaggedExperience")]
pub struct TaggedExperience {
    pub content: String,
    pub emotional_weight: f64,
    pub valence: f64,
    pub arousal: f64,
    pub context: Vec<String>,
    pub timestamp: u64,
}

// ─── Layer 4: Hippocampus → Neuron Layer ─────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifUnitEnum))]
pub enum ConnectionType {
    Excitatory,
    Inhibitory,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifStruct))]
#[cfg_attr(feature = "nif", module = "Odysseus.Signals.WeightUpdate")]
pub struct WeightUpdate {
    pub source_neurons: Vec<String>,
    pub target_neurons: Vec<String>,
    pub delta_weights: Vec<f64>,
    pub consolidation_score: f64,
    pub connection_type: ConnectionType,
}

// ─── Layer 5: Frontal Lobe → Basal Ganglia ───────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifStruct))]
#[cfg_attr(feature = "nif", module = "Odysseus.Signals.ActionCandidate")]
pub struct ActionCandidate {
    pub action: String,
    pub expected_reward: f64,
    pub confidence: f64,
    pub risk_level: f64,
    pub reasoning: String,
    pub context: Vec<String>,
}

// ─── Layer 6: Basal Ganglia → Cerebellum ─────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifStruct))]
#[cfg_attr(feature = "nif", module = "Odysseus.Signals.ExpectedState")]
pub struct ExpectedState {
    pub step: u32,
    pub description: String,
    pub confidence: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifStruct))]
#[cfg_attr(feature = "nif", module = "Odysseus.Signals.MotorPlan")]
pub struct MotorPlan {
    pub action: String,
    pub predicted_outcome: String,
    pub timeline_ms: u64,
    pub expected_states: Vec<ExpectedState>,
}

// ─── Layer 7: Cerebellum → Basal Ganglia + Frontal (feedback) ─

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifUnitEnum))]
pub enum ErrorDirection {
    Overestimate,
    Underestimate,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifStruct))]
#[cfg_attr(feature = "nif", module = "Odysseus.Signals.Adjustment")]
pub struct Adjustment {
    pub target: String,
    pub delta: f64,
    pub reason: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifStruct))]
#[cfg_attr(feature = "nif", module = "Odysseus.Signals.ErrorSignal")]
pub struct ErrorSignal {
    pub expected: String,
    pub actual: String,
    pub magnitude: f64,
    pub direction: ErrorDirection,
    pub adjustments: Vec<Adjustment>,
}

// ─── Neuron Activation (recall process) ───────────────────────

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifStruct))]
#[cfg_attr(feature = "nif", module = "Odysseus.Signals.SpreadTarget")]
pub struct SpreadTarget {
    pub target_id: String,
    pub weight: f64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[cfg_attr(feature = "nif", derive(rustler::NifStruct))]
#[cfg_attr(feature = "nif", module = "Odysseus.Signals.ActivationSignal")]
pub struct ActivationSignal {
    pub neuron_id: String,
    pub activation_level: f64,
    pub trigger: String,
    pub spread_to: Vec<SpreadTarget>,
}

// ─── Motor Program (Basal Ganglia habits) ─────────────────────
// No NifStruct — contains serde_json::Value which can't cross NIF boundary.
// Used internally by basal ganglia (ResourceArc pattern).

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct MotorProgram {
    pub name: String,
    pub trigger: serde_json::Value,
    pub steps: Vec<String>,
    pub confidence: f64,
    pub execution_count: u64,
    pub last_used: u64,
}
