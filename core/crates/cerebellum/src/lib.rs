use rustler::{Env, ResourceArc};
use signal_types::{Adjustment, ErrorDirection, MotorPlan};
use std::collections::HashMap;
use std::sync::RwLock;

// ─── Internal types ──────────────────────────────────────────

struct PredictionRecord {
    predicted_outcome: String,
    confidence: f64,
}

struct StoredError {
    magnitude: f64,
    action: String,
}

struct PredictorInner {
    predictions: HashMap<String, PredictionRecord>,
    error_history: Vec<StoredError>,
    calibration_factor: f64,
}

pub struct PredictorRes {
    inner: RwLock<PredictorInner>,
}

// ─── NIF functions ───────────────────────────────────────────

#[rustler::nif]
fn new_predictor() -> ResourceArc<PredictorRes> {
    ResourceArc::new(PredictorRes {
        inner: RwLock::new(PredictorInner {
            predictions: HashMap::new(),
            error_history: Vec::new(),
            calibration_factor: 1.0,
        }),
    })
}

/// Store a prediction for a motor plan action.
#[rustler::nif]
fn predict(res: ResourceArc<PredictorRes>, plan: MotorPlan) -> bool {
    let mut inner = res.inner.write().unwrap();
    let calibrated = (plan
        .expected_states
        .first()
        .map(|s| s.confidence)
        .unwrap_or(0.5)
        * inner.calibration_factor)
        .min(1.0);

    inner.predictions.insert(
        plan.action,
        PredictionRecord {
            predicted_outcome: plan.predicted_outcome,
            confidence: calibrated,
        },
    );
    true
}

/// Observe actual outcome and generate ErrorSignal.
#[rustler::nif]
fn observe_outcome(
    res: ResourceArc<PredictorRes>,
    action: String,
    actual: String,
) -> Option<CerebellumErrorSignal> {
    let mut inner = res.inner.write().unwrap();

    // Step 1: Extract prediction data, then remove it
    let (predicted_outcome, confidence) = {
        let record = inner.predictions.get(&action)?;
        (record.predicted_outcome.clone(), record.confidence)
    };

    let similarity = text_similarity(&predicted_outcome, &actual);
    let magnitude = 1.0 - similarity;

    // Step 2: Update state
    inner.calibration_factor = (inner.calibration_factor * 0.95) + (similarity * 0.05);
    inner.calibration_factor = inner.calibration_factor.clamp(0.1, 1.5);

    inner.error_history.push(StoredError {
        magnitude,
        action: action.clone(),
    });
    if inner.error_history.len() > 50 {
        inner.error_history.remove(0);
    }

    let direction = if confidence > similarity {
        ErrorDirection::Overestimate
    } else {
        ErrorDirection::Underestimate
    };

    // Step 3: Generate adjustments
    let mut adjustments = Vec::new();

    if magnitude > 0.5 {
        adjustments.push(Adjustment {
            target: format!("frontal_strategy:{}", action),
            delta: -magnitude * 0.3,
            reason: "Large prediction error — revise strategy".to_string(),
        });
    }

    let repeat_errors = inner
        .error_history
        .iter()
        .filter(|e| e.action == action && e.magnitude > 0.3)
        .count();
    if repeat_errors >= 3 {
        adjustments.push(Adjustment {
            target: format!("basal_habit:{}", action),
            delta: -0.2,
            reason: format!("Repeated errors ({}) — weaken habit", repeat_errors),
        });
    }

    if magnitude < 0.2 {
        adjustments.push(Adjustment {
            target: format!("basal_habit:{}", action),
            delta: 0.1,
            reason: "Accurate prediction — reinforce habit".to_string(),
        });
    }

    Some(CerebellumErrorSignal {
        expected: predicted_outcome,
        actual,
        magnitude,
        direction,
        adjustments,
    })
}

/// Get current calibration factor (1.0 = well-calibrated).
#[rustler::nif]
fn calibration(res: ResourceArc<PredictorRes>) -> f64 {
    res.inner.read().unwrap().calibration_factor
}

/// Get prediction count and average error magnitude.
#[rustler::nif]
fn stats(res: ResourceArc<PredictorRes>) -> CerebellumStats {
    let inner = res.inner.read().unwrap();
    let avg = if inner.error_history.is_empty() {
        0.0
    } else {
        inner.error_history.iter().map(|e| e.magnitude).sum::<f64>()
            / inner.error_history.len() as f64
    };
    CerebellumStats {
        active_predictions: inner.predictions.len(),
        avg_error_magnitude: avg,
        calibration: inner.calibration_factor,
    }
}

// ─── Helpers ─────────────────────────────────────────────────

fn text_similarity(a: &str, b: &str) -> f64 {
    let set_a: std::collections::HashSet<&str> = a.split_whitespace().collect();
    let set_b: std::collections::HashSet<&str> = b.split_whitespace().collect();
    if set_a.is_empty() || set_b.is_empty() {
        return 0.0;
    }
    let intersection = set_a.intersection(&set_b).count();
    let union = set_a.union(&set_b).count();
    intersection as f64 / union as f64
}

// ─── NIF result types ────────────────────────────────────────

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "Odysseus.Cerebellum.ErrorSignal"]
pub struct CerebellumErrorSignal {
    pub expected: String,
    pub actual: String,
    pub magnitude: f64,
    pub direction: ErrorDirection,
    pub adjustments: Vec<Adjustment>,
}

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "Odysseus.Cerebellum.Stats"]
pub struct CerebellumStats {
    pub active_predictions: usize,
    pub avg_error_magnitude: f64,
    pub calibration: f64,
}

// ─── Module registration ─────────────────────────────────────

fn load(env: Env, _term: rustler::Term) -> bool {
    rustler::resource!(PredictorRes, env);
    true
}

rustler::init!(
    "Elixir.Odysseus.Cerebellum.Nif",
    [new_predictor, predict, observe_outcome, calibration, stats],
    load = load
);
