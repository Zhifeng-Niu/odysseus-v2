use rustler::ResourceArc;
use signal_types::{ActivationSignal, SpreadTarget, TaggedExperience};
use sparse_matrix::{Connection, SparseMatrix};
use std::collections::HashMap;
use std::fs;
use std::path::Path;
use std::sync::RwLock;

const DEFAULT_ACTIVATION_THRESHOLD: f64 = 0.3;
const HEBBIAN_DELTA: f64 = 0.05;
const MAX_WEIGHT: f64 = 1.0;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct Neuron {
    pub id: String,
    pub features: Vec<f64>,
    pub activation_threshold: f64,
    pub last_activated: u64,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct NeuronLayerSnapshot {
    pub neurons: HashMap<String, Neuron>,
    pub connections: HashMap<String, HashMap<String, Connection>>,
    pub decay_rate: f64,
    pub min_weight: f64,
    pub max_hops: u32,
    pub activation_k: usize,
}

pub struct NeuronLayerInner {
    pub neurons: HashMap<String, Neuron>,
    pub connections: SparseMatrix,
    pub decay_rate: f64,
    pub min_weight: f64,
    pub max_hops: u32,
    pub activation_k: usize,
}

impl NeuronLayerInner {
    fn to_snapshot(&self) -> NeuronLayerSnapshot {
        let rows: HashMap<String, HashMap<String, Connection>> = self
            .connections
            .rows()
            .map(|(src, targets)| {
                let entries = targets
                    .iter()
                    .map(|(tgt, conn)| (tgt.clone(), conn.clone()))
                    .collect();
                (src.clone(), entries)
            })
            .collect();

        NeuronLayerSnapshot {
            neurons: self.neurons.clone(),
            connections: rows,
            decay_rate: self.decay_rate,
            min_weight: self.min_weight,
            max_hops: self.max_hops,
            activation_k: self.activation_k,
        }
    }

    fn from_snapshot(snap: NeuronLayerSnapshot) -> Self {
        let mut matrix = SparseMatrix::new();
        for (src, targets) in &snap.connections {
            for (tgt, conn) in targets {
                matrix.set(src.clone(), tgt.clone(), conn.clone());
            }
        }
        Self {
            neurons: snap.neurons,
            connections: matrix,
            decay_rate: snap.decay_rate,
            min_weight: snap.min_weight,
            max_hops: snap.max_hops,
            activation_k: snap.activation_k,
        }
    }
}

pub struct NeuronLayerRes {
    inner: RwLock<NeuronLayerInner>,
}

impl NeuronLayerRes {
    fn new() -> Self {
        Self {
            inner: RwLock::new(NeuronLayerInner {
                neurons: HashMap::new(),
                connections: SparseMatrix::new(),
                decay_rate: 0.9999,
                min_weight: 0.01,
                max_hops: 3,
                activation_k: 10,
            }),
        }
    }
}

// ─── Core computation ─────────────────────────────────────────

fn recall_inner(layer: &NeuronLayerInner, cue: &[f64]) -> Vec<ActivationSignal> {
    let mut scored: Vec<(String, f64)> = layer
        .neurons
        .iter()
        .map(|(id, neuron)| (id.clone(), cosine_similarity(cue, &neuron.features)))
        .filter(|(_, score)| *score > 0.1)
        .collect();

    scored.sort_by(|a, b| b.1.partial_cmp(&a.1).unwrap());
    scored.truncate(layer.activation_k);

    let mut activated = Vec::new();
    for (id, level) in &scored {
        let spread: Vec<SpreadTarget> = layer
            .connections
            .neighbors(id)
            .map(|(target, conn)| SpreadTarget {
                target_id: target.clone(),
                weight: conn.weight,
            })
            .collect();

        activated.push(ActivationSignal {
            neuron_id: id.clone(),
            activation_level: *level,
            trigger: "recall".to_string(),
            spread_to: spread,
        });
    }

    let spread_results = spread_activation_inner(layer, &scored);
    activated.extend(spread_results);
    activated
}

fn spread_activation_inner(
    layer: &NeuronLayerInner,
    seeds: &[(String, f64)],
) -> Vec<ActivationSignal> {
    let mut visited: HashMap<String, f64> = HashMap::new();
    for (id, level) in seeds {
        visited.insert(id.clone(), *level);
    }

    let mut frontier: Vec<(String, f64)> = seeds.to_vec();

    for _hop in 0..layer.max_hops {
        let mut next_frontier = Vec::new();
        for (source_id, source_level) in &frontier {
            for (target_id, conn) in layer.connections.neighbors(source_id) {
                let sign = if conn.connection_type == sparse_matrix::ConnectionType::Inhibitory { -1.0 } else { 1.0 };
                let propagated = source_level * conn.weight * sign;
                if propagated.abs() < DEFAULT_ACTIVATION_THRESHOLD {
                    continue;
                }
                let current = visited.entry(target_id.clone()).or_insert(0.0);
                if propagated > *current {
                    *current = propagated;
                    next_frontier.push((target_id.clone(), propagated));
                }
            }
        }
        if next_frontier.is_empty() {
            break;
        }
        frontier = next_frontier;
    }

    visited
        .into_iter()
        .filter(|(id, _)| seeds.iter().all(|(sid, _)| sid != id))
        .filter(|(_, level)| *level > 0.0)
        .map(|(id, level)| ActivationSignal {
            neuron_id: id,
            activation_level: level,
            trigger: "spread".to_string(),
            spread_to: vec![],
        })
        .collect()
}

fn cosine_similarity(a: &[f64], b: &[f64]) -> f64 {
    if a.len() != b.len() || a.is_empty() {
        return 0.0;
    }
    let dot: f64 = a.iter().zip(b.iter()).map(|(x, y)| x * y).sum();
    let norm_a: f64 = a.iter().map(|x| x * x).sum::<f64>().sqrt();
    let norm_b: f64 = b.iter().map(|x| x * x).sum::<f64>().sqrt();
    if norm_a == 0.0 || norm_b == 0.0 {
        return 0.0;
    }
    dot / (norm_a * norm_b)
}

// ─── NIF functions ────────────────────────────────────────────

#[rustler::nif]
fn new_layer() -> ResourceArc<NeuronLayerRes> {
    ResourceArc::new(NeuronLayerRes::new())
}

#[rustler::nif]
fn recall(layer: ResourceArc<NeuronLayerRes>, cue: Vec<f64>) -> Vec<ActivationSignal> {
    let inner = layer.inner.read().unwrap();
    recall_inner(&inner, &cue)
}

#[rustler::nif]
fn learn(
    layer: ResourceArc<NeuronLayerRes>,
    _experience: TaggedExperience,
    features: Vec<f64>,
    now: u64,
) -> String {
    let mut inner = layer.inner.write().unwrap();
    let neuron_id = format!("n_{}", now);

    let neuron = Neuron {
        id: neuron_id.clone(),
        features,
        activation_threshold: DEFAULT_ACTIVATION_THRESHOLD,
        last_activated: now,
    };

    let mut related = Vec::new();
    for (existing_id, existing) in &inner.neurons {
        let sim = cosine_similarity(&neuron.features, &existing.features);
        if sim > 0.5 {
            related.push((existing_id.clone(), sim));
        }
    }

    for (target_id, weight) in &related {
        inner.connections.set(
            neuron_id.clone(),
            target_id.clone(),
            Connection {
                weight: *weight,
                connection_type: sparse_matrix::ConnectionType::Excitatory,
                created_at: now,
                reinforced_at: now,
            },
        );
        inner.connections.set(
            target_id.clone(),
            neuron_id.clone(),
            Connection {
                weight: *weight,
                connection_type: sparse_matrix::ConnectionType::Excitatory,
                created_at: now,
                reinforced_at: now,
            },
        );
    }

    inner.neurons.insert(neuron_id.clone(), neuron);
    neuron_id
}

/// Hebbian reinforcement: co-activated neurons strengthen their connections.
#[rustler::nif]
fn reinforce(
    layer: ResourceArc<NeuronLayerRes>,
    neuron_ids: Vec<String>,
    levels: Vec<f64>,
    now: u64,
) -> usize {
    let mut inner = layer.inner.write().unwrap();
    let mut reinforced = 0;

    for i in 0..neuron_ids.len() {
        for j in (i + 1)..neuron_ids.len() {
            let id_a = &neuron_ids[i];
            let id_b = &neuron_ids[j];
            let level_a = levels.get(i).copied().unwrap_or(0.0);
            let level_b = levels.get(j).copied().unwrap_or(0.0);
            let delta = HEBBIAN_DELTA * level_a * level_b;

            if let Some(conn) = inner.connections.get_mut(id_a, id_b) {
                conn.weight = (conn.weight + delta).min(MAX_WEIGHT);
                conn.reinforced_at = now;
                reinforced += 1;
            }

            if let Some(conn) = inner.connections.get_mut(id_b, id_a) {
                conn.weight = (conn.weight + delta).min(MAX_WEIGHT);
                conn.reinforced_at = now;
                reinforced += 1;
            }
        }
    }

    for id in &neuron_ids {
        if let Some(neuron) = inner.neurons.get_mut(id) {
            neuron.last_activated = now;
        }
    }

    reinforced
}

#[rustler::nif]
fn tick_decay(layer: ResourceArc<NeuronLayerRes>) -> usize {
    let mut inner = layer.inner.write().unwrap();
    let (rate, min) = (inner.decay_rate, inner.min_weight);
    inner.connections.decay_all(rate, min)
}

/// Save neuron layer to a JSON file.
#[rustler::nif]
fn save(layer: ResourceArc<NeuronLayerRes>, path: String) -> bool {
    let inner = layer.inner.read().unwrap();
    let snapshot = inner.to_snapshot();
    match serde_json::to_string_pretty(&snapshot) {
        Ok(json) => fs::write(Path::new(&path), json).is_ok(),
        Err(_) => false,
    }
}

/// Load neuron layer from a JSON file. Returns (neuron_count, connection_count) on success.
#[rustler::nif]
fn load_layer(layer: ResourceArc<NeuronLayerRes>, path: String) -> (bool, usize, usize) {
    let data = match fs::read_to_string(Path::new(&path)) {
        Ok(d) => d,
        Err(_) => return (false, 0, 0),
    };

    let snapshot: NeuronLayerSnapshot = match serde_json::from_str(&data) {
        Ok(s) => s,
        Err(_) => return (false, 0, 0),
    };

    let loaded = NeuronLayerInner::from_snapshot(snapshot);
    let count = (loaded.neurons.len(), loaded.connections.total_connections());

    let mut inner = layer.inner.write().unwrap();
    *inner = loaded;

    (true, count.0, count.1)
}

#[rustler::nif]
fn stats(layer: ResourceArc<NeuronLayerRes>) -> (usize, usize) {
    let inner = layer.inner.read().unwrap();
    (inner.neurons.len(), inner.connections.total_connections())
}

fn on_load(env: rustler::Env, _term: rustler::Term) -> bool {
    rustler::resource!(NeuronLayerRes, env);
    true
}

rustler::init!(
    "Elixir.Odysseus.Neurons.Nif",
    [new_layer, recall, learn, reinforce, tick_decay, save, load_layer, stats],
    load = on_load
);
