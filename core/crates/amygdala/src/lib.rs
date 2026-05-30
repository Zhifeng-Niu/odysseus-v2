use rustler::{Env, ResourceArc};
use signal_types::EmotionalTag;
use std::sync::RwLock;

struct EmotionalStateInner {
    valence: f64,
    arousal: f64,
    threat_baseline: f64,
    opportunity_baseline: f64,
}

pub struct EmotionalStateRes {
    inner: RwLock<EmotionalStateInner>,
}

#[rustler::nif]
fn new_state() -> ResourceArc<EmotionalStateRes> {
    ResourceArc::new(EmotionalStateRes {
        inner: RwLock::new(EmotionalStateInner {
            valence: 0.0,
            arousal: 0.3,
            threat_baseline: 0.1,
            opportunity_baseline: 0.1,
        }),
    })
}

#[rustler::nif]
fn evaluate(res: ResourceArc<EmotionalStateRes>, text: String) -> EmotionalTag {
    let mut inner = res.inner.write().unwrap();

    let valence_shift = detect_valence(&text);
    let arousal_shift = detect_arousal(&text);
    let threat_level = detect_threat(&text);
    let opportunity = detect_opportunity(&text);

    inner.valence = (inner.valence * 0.8) + (valence_shift * 0.2);
    inner.arousal = (inner.arousal * 0.8) + (arousal_shift * 0.2);
    inner.valence = inner.valence.clamp(-1.0, 1.0);
    inner.arousal = inner.arousal.clamp(0.0, 1.0);

    let tag = EmotionalTag {
        valence: inner.valence,
        arousal: inner.arousal,
        urgency: arousal_shift * threat_level,
        threat: threat_level,
        opportunity,
        source: "amygdala".to_string(),
    };

    inner.threat_baseline = (inner.threat_baseline * 0.9) + (threat_level * 0.1);
    inner.opportunity_baseline = (inner.opportunity_baseline * 0.9) + (opportunity * 0.1);

    tag
}

#[rustler::nif]
fn state_summary(res: ResourceArc<EmotionalStateRes>) -> (f64, f64, f64, f64) {
    let inner = res.inner.read().unwrap();
    (
        inner.valence,
        inner.arousal,
        inner.threat_baseline,
        inner.opportunity_baseline,
    )
}

fn detect_valence(text: &str) -> f64 {
    let positive = ["good", "great", "happy", "love", "excellent", "wonderful", "thanks"];
    let negative = ["bad", "hate", "angry", "terrible", "awful", "error", "fail", "crash"];
    let lower = text.to_lowercase();
    let pos = positive.iter().filter(|w| lower.contains(*w)).count();
    let neg = negative.iter().filter(|w| lower.contains(*w)).count();
    if pos + neg == 0 { return 0.0; }
    (pos as f64 - neg as f64) / (pos + neg).max(1) as f64
}

fn detect_arousal(text: &str) -> f64 {
    let markers = ["!", "urgent", "asap", "now", "immediately", "critical", "emergency"];
    let lower = text.to_lowercase();
    (markers.iter().filter(|w| lower.contains(*w)).count() as f64 / 3.0).min(1.0)
}

fn detect_threat(text: &str) -> f64 {
    let words = ["danger", "risk", "warning", "error", "crash", "fail", "broken", "kill"];
    let lower = text.to_lowercase();
    (words.iter().filter(|w| lower.contains(*w)).count() as f64 / 2.0).min(1.0)
}

fn detect_opportunity(text: &str) -> f64 {
    let words = ["opportunity", "improve", "optimize", "feature", "new", "create", "build"];
    let lower = text.to_lowercase();
    (words.iter().filter(|w| lower.contains(*w)).count() as f64 / 2.0).min(1.0)
}

fn load(env: Env, _term: rustler::Term) -> bool {
    rustler::resource!(EmotionalStateRes, env);
    true
}

rustler::init!(
    "Elixir.Odysseus.Amygdala.Nif",
    [new_state, evaluate, state_summary],
    load = load
);
