/// A synapse is a pure function that transforms one signal format into another.
/// Each structure boundary is a synapse — the format change IS the computation.
pub trait Synapse<Input, Output> {
    fn transform(&self, input: Input, context: &SystemState) -> Output;
}

/// Shared system state passed to all synapses for context-aware transformations.
#[derive(Debug, Clone)]
pub struct SystemState {
    pub arousal_level: f64,
    pub attention_focus: f64,
    pub token_budget_remaining: f64,
    pub memory_pressure: f64,
    pub interaction_gap_ms: u64,
    pub emotional_state: EmotionalState,
}

#[derive(Debug, Clone)]
pub struct EmotionalState {
    pub valence: f64,
    pub arousal: f64,
    pub dominant_emotion: String,
}
