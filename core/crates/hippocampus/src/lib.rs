use rustler::{Env, ResourceArc};
use signal_types::{ConnectionType, TaggedExperience, WeightUpdate};
use sparse_matrix::SparseMatrix;
use std::collections::HashMap;
use std::sync::RwLock;

// ─── Internal types ──────────────────────────────────────────

struct NeuronGroup {
    id: String,
    feature_ids: Vec<String>,
    content: String,
    emotional_weight: f64,
    valence: f64,
    arousal: f64,
    access_count: u32,
    context: Vec<String>,
    created_at: u64,
    last_accessed: u64,
}

struct HippocampusInner {
    /// Short-term buffer: recent experiences awaiting consolidation.
    short_term: HashMap<String, NeuronGroup>,
    /// Long-term memory: sparse neuron network with weighted connections.
    long_term: SparseMatrix,
    /// Neuron metadata: content and context for each neuron in the network.
    neuron_meta: HashMap<String, NeuronMeta>,
    /// Pattern separation threshold — Jaccard overlap above this means "same pattern".
    separation_threshold: f64,
    /// Activation threshold for recall spreading.
    activation_threshold: f64,
    /// Spreading decay per hop.
    spread_decay: f64,
    /// Maximum hops for activation spreading.
    max_spread_hops: usize,
    /// Maximum connection weight.
    max_weight: f64,
    /// Decay rate for short-term memories.
    decay_rate: f64,
    /// Consolidation: minimum access count or emotional weight to promote.
    consolidation_min_access: u32,
    consolidation_emotion_threshold: f64,
}

struct NeuronMeta {
    content: String,
    context: Vec<String>,
    emotional_weight: f64,
    valence: f64,
    arousal: f64,
    activation_count: u64,
    created_at: u64,
}

pub struct HippocampusRes {
    inner: RwLock<HippocampusInner>,
}

// ─── NIF functions ───────────────────────────────────────────

#[rustler::nif]
fn new_store() -> ResourceArc<HippocampusRes> {
    ResourceArc::new(HippocampusRes {
        inner: RwLock::new(HippocampusInner {
            short_term: HashMap::new(),
            long_term: SparseMatrix::new(),
            neuron_meta: HashMap::new(),
            separation_threshold: 0.7,
            activation_threshold: 0.15,
            spread_decay: 0.6,
            max_spread_hops: 3,
            max_weight: 1.0,
            decay_rate: 0.995,
            consolidation_min_access: 3,
            consolidation_emotion_threshold: 0.6,
        }),
    })
}

/// Encode a TaggedExperience into the short-term buffer.
/// Extracts features from content, creates a neuron group with pattern separation.
#[rustler::nif]
fn store(
    res: ResourceArc<HippocampusRes>,
    experience: TaggedExperience,
    now: u64,
) -> String {
    let mut inner = res.inner.write().unwrap();
    let id = format!("mem_{}", now);

    // Extract features: split content into tokens, use bigrams + unigrams
    let features = extract_features(&experience.content);

    // Pattern separation: check if a similar neuron group already exists
    let is_duplicate = inner
        .short_term
        .values()
        .any(|g| feature_overlap(&features, &g.feature_ids) > inner.separation_threshold);

    // Even if similar, store separately (pattern separation).
    // Consolidation will merge later if warranted.
    let group = NeuronGroup {
        id: id.clone(),
        feature_ids: features,
        content: experience.content,
        emotional_weight: experience.emotional_weight,
        valence: experience.valence,
        arousal: experience.arousal,
        access_count: 0,
        context: experience.context,
        created_at: now,
        last_accessed: now,
    };

    inner.short_term.insert(id.clone(), group);
    id
}

/// Pattern completion / activation spreading recall.
/// Given a cue text, encode it as features, seed activation, and spread through the network.
/// Returns recalled memory content with activation levels.
#[rustler::nif]
fn recall(
    res: ResourceArc<HippocampusRes>,
    cue: String,
    now: u64,
) -> Vec<RecallResult> {
    let mut inner = res.inner.write().unwrap();

    // Step 1: Encode cue as feature activation seeds
    let cue_features = extract_features(&cue);
    let seeds: Vec<(String, f64)> = cue_features
        .iter()
        .filter_map(|f| {
            // Each feature neuron's initial activation is its emotional salience
            inner
                .neuron_meta
                .get(f)
                .map(|meta| (f.clone(), meta.emotional_weight.min(1.0).max(0.1)))
        })
        .collect();

    // Also seed from short-term matches
    let short_term_seeds: Vec<(String, f64)> = inner
        .short_term
        .iter()
        .filter_map(|(id, group)| {
            let overlap = feature_overlap(&cue_features, &group.feature_ids);
            if overlap > 0.2 {
                Some((id.clone(), overlap * group.emotional_weight))
            } else {
                None
            }
        })
        .collect();

    let all_seeds: Vec<(String, f64)> = seeds
        .into_iter()
        .chain(short_term_seeds.into_iter())
        .collect();

    if all_seeds.is_empty() {
        return Vec::new();
    }

    // Step 2: Spread activation through long-term network
    let activated = inner.long_term.spread_activation(
        &all_seeds,
        inner.activation_threshold,
        inner.max_spread_hops,
        inner.spread_decay,
    );

    // Step 3: Collect recalled content from activated neurons
    let mut results: Vec<RecallResult> = activated
        .iter()
        .filter_map(|(neuron_id, level)| {
            // Check neuron_meta first (long-term)
            if let Some(meta) = inner.neuron_meta.get_mut(neuron_id) {
                meta.activation_count += 1;
                return Some(RecallResult {
                    id: neuron_id.clone(),
                    content: meta.content.clone(),
                    activation: *level,
                    emotional_weight: meta.emotional_weight,
                    context: meta.context.clone(),
                });
            }
            // Check short_term
            if let Some(group) = inner.short_term.get_mut(neuron_id) {
                group.access_count += 1;
                group.last_accessed = now;
                return Some(RecallResult {
                    id: group.id.clone(),
                    content: group.content.clone(),
                    activation: *level,
                    emotional_weight: group.emotional_weight,
                    context: group.context.clone(),
                });
            }
            None
        })
        .collect();

    // Sort by activation level descending
    results.sort_by(|a, b| b.activation.partial_cmp(&a.activation).unwrap());
    results.truncate(10);
    results
}

/// Consolidate short-term memories into long-term sparse network.
/// High emotional weight or frequently accessed memories get promoted.
/// Repeated patterns strengthen existing connections (Hebbian), new patterns create new ones.
#[rustler::nif]
fn consolidate(res: ResourceArc<HippocampusRes>, now: u64) -> ConsolidationReport {
    let inner = &mut *res.inner.write().unwrap();

    let eligible: Vec<String> = inner
        .short_term
        .iter()
        .filter(|(_, g)| {
            g.access_count >= inner.consolidation_min_access
                || g.emotional_weight > inner.consolidation_emotion_threshold
        })
        .map(|(id, _)| id.clone())
        .collect();

    let mut consolidated_count = 0usize;
    let mut reinforced_count = 0usize;
    let mut weight_updates: Vec<WeightUpdate> = Vec::new();

    for id in &eligible {
        let group = match inner.short_term.remove(id) {
            Some(g) => g,
            None => continue,
        };

        let consolidation_score = (group.emotional_weight * 0.6
            + (group.access_count as f64 / 10.0).min(0.4))
        .min(1.0);

        // Check if similar pattern already exists in long-term
        let existing = inner
            .long_term
            .find_overlapping_group(&group.feature_ids);

        let center_id = if let Some((existing_id, overlap)) = existing {
            if overlap > inner.separation_threshold {
                // Same pattern — reinforce existing connections (Hebbian learning)
                for feature_id in &group.feature_ids {
                    inner.long_term.hebbian_reinforce(
                        &existing_id,
                        feature_id,
                        consolidation_score * 0.1,
                        now,
                        inner.max_weight,
                    );
                    inner.long_term.hebbian_reinforce(
                        feature_id,
                        &existing_id,
                        consolidation_score * 0.05,
                        now,
                        inner.max_weight,
                    );
                }

                // Update meta emotional weight if this memory was stronger
                if let Some(meta) = inner.neuron_meta.get_mut(&existing_id) {
                    meta.emotional_weight =
                        (meta.emotional_weight + group.emotional_weight) / 2.0;
                    meta.activation_count += 1;
                }

                reinforced_count += 1;
                existing_id
            } else {
                // Different enough — create new neuron group
                create_new_neuron(inner, &group, consolidation_score, now)
            }
        } else {
            // No similar pattern — create new neuron group
            create_new_neuron(inner, &group, consolidation_score, now)
        };

        // Generate WeightUpdate signal for the neuron layer
        let (sources, deltas): (Vec<String>, Vec<f64>) = group
            .feature_ids
            .iter()
            .map(|f| (f.clone(), consolidation_score * 0.1))
            .unzip();

        weight_updates.push(WeightUpdate {
            source_neurons: vec![center_id],
            target_neurons: sources,
            delta_weights: deltas,
            consolidation_score,
            connection_type: ConnectionType::Excitatory,
        });

        consolidated_count += 1;
    }

    ConsolidationReport {
        consolidated: consolidated_count,
        reinforced: reinforced_count,
        updates: weight_updates,
    }
}

/// Apply time-based decay to short-term memories. Returns count of pruned entries.
#[rustler::nif]
fn tick_decay(res: ResourceArc<HippocampusRes>) -> usize {
    let inner = &mut *res.inner.write().unwrap();
    let decay = inner.decay_rate;
    let mut pruned = 0;

    inner.short_term.retain(|_, group| {
        group.emotional_weight *= decay;
        if group.emotional_weight < 0.01 {
            pruned += 1;
            false
        } else {
            true
        }
    });

    // Also decay long-term connections (slower)
    let lt_pruned = inner.long_term.decay_all(0.9999, 0.01);
    pruned + lt_pruned
}

/// Get memory statistics.
#[rustler::nif]
fn stats(res: ResourceArc<HippocampusRes>) -> MemoryStats {
    let inner = res.inner.read().unwrap();
    let long_term_neurons = inner.neuron_meta.len();
    let long_term_connections = inner.long_term.total_connections();
    let short_term_count = inner.short_term.len();

    let avg_emotional = inner
        .short_term
        .values()
        .map(|g| g.emotional_weight)
        .chain(inner.neuron_meta.values().map(|m| m.emotional_weight))
        .sum::<f64>()
        / (short_term_count + long_term_neurons).max(1) as f64;

    MemoryStats {
        short_term: short_term_count,
        long_term_neurons,
        long_term_connections,
        avg_emotional_weight: avg_emotional,
    }
}

// ─── Helper functions ────────────────────────────────────────

fn create_new_neuron(
    inner: &mut HippocampusInner,
    group: &NeuronGroup,
    consolidation_score: f64,
    now: u64,
) -> String {
    let center_id = group.id.clone();

    // Store metadata
    inner.neuron_meta.insert(
        center_id.clone(),
        NeuronMeta {
            content: group.content.clone(),
            context: group.context.clone(),
            emotional_weight: group.emotional_weight,
            valence: group.valence,
            arousal: group.arousal,
            activation_count: 0,
            created_at: now,
        },
    );

    // Create bidirectional connections: center ↔ features
    for feature_id in &group.feature_ids {
        inner.long_term.set(
            center_id.clone(),
            feature_id.clone(),
            sparse_matrix::Connection {
                weight: consolidation_score,
                connection_type: sparse_matrix::ConnectionType::Excitatory,
                created_at: now,
                reinforced_at: now,
            },
        );
        inner.long_term.set(
            feature_id.clone(),
            center_id.clone(),
            sparse_matrix::Connection {
                weight: consolidation_score * 0.5,
                connection_type: sparse_matrix::ConnectionType::Excitatory,
                created_at: now,
                reinforced_at: now,
            },
        );

        // Store feature metadata (lightweight)
        inner
            .neuron_meta
            .entry(feature_id.clone())
            .or_insert_with(|| NeuronMeta {
                content: feature_id.clone(),
                context: Vec::new(),
                emotional_weight: consolidation_score * 0.3,
                valence: 0.0,
                arousal: 0.0,
                activation_count: 0,
                created_at: now,
            });
    }

    center_id
}

/// Extract features from text: unigrams (len>2) + bigrams.
/// This is the "encoding" step — raw text → sparse feature vector.
fn extract_features(text: &str) -> Vec<String> {
    let words: Vec<&str> = text
        .split_whitespace()
        .filter(|w| w.len() > 2)
        .collect();

    let mut features = Vec::with_capacity(words.len() * 2);

    // Unigrams
    for w in &words {
        features.push(format!("w:{}", w.to_lowercase()));
    }

    // Bigrams (captures word order)
    for window in words.windows(2) {
        features.push(format!("bg:{}_{}", window[0].to_lowercase(), window[1].to_lowercase()));
    }

    features
}

/// Compute Jaccard overlap between two feature sets.
fn feature_overlap(a: &[String], b: &[String]) -> f64 {
    if a.is_empty() || b.is_empty() {
        return 0.0;
    }
    let set_a: std::collections::HashSet<&str> = a.iter().map(|s| s.as_str()).collect();
    let set_b: std::collections::HashSet<&str> = b.iter().map(|s| s.as_str()).collect();
    let intersection = set_a.intersection(&set_b).count();
    let union = set_a.union(&set_b).count();
    intersection as f64 / union as f64
}

// ─── NIF result types ────────────────────────────────────────

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "Odysseus.Hippocampus.RecallResult"]
pub struct RecallResult {
    pub id: String,
    pub content: String,
    pub activation: f64,
    pub emotional_weight: f64,
    pub context: Vec<String>,
}

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "Odysseus.Hippocampus.ConsolidationReport"]
pub struct ConsolidationReport {
    pub consolidated: usize,
    pub reinforced: usize,
    pub updates: Vec<WeightUpdate>,
}

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "Odysseus.Hippocampus.MemoryStats"]
pub struct MemoryStats {
    pub short_term: usize,
    pub long_term_neurons: usize,
    pub long_term_connections: usize,
    pub avg_emotional_weight: f64,
}

// ─── NIF module registration ─────────────────────────────────

fn load(env: Env, _term: rustler::Term) -> bool {
    rustler::resource!(HippocampusRes, env);
    true
}

rustler::init!(
    "Elixir.Odysseus.Hippocampus.Nif",
    [new_store, store, recall, consolidate, tick_decay, stats],
    load = load
);
