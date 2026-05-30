use serde::{Deserialize, Serialize};
use std::collections::{HashMap, HashSet};

#[derive(Debug, Clone, Copy, PartialEq, Serialize, Deserialize)]
pub enum ConnectionType {
    Excitatory,
    Inhibitory,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Connection {
    pub weight: f64,
    pub connection_type: ConnectionType,
    pub created_at: u64,
    pub reinforced_at: u64,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SparseMatrix {
    rows: HashMap<String, HashMap<String, Connection>>,
}

impl SparseMatrix {
    pub fn new() -> Self {
        Self {
            rows: HashMap::new(),
        }
    }

    pub fn get(&self, source: &str, target: &str) -> Option<&Connection> {
        self.rows.get(source).and_then(|row| row.get(target))
    }

    pub fn set(&mut self, source: String, target: String, connection: Connection) {
        self.rows
            .entry(source)
            .or_default()
            .insert(target, connection);
    }

    pub fn remove(&mut self, source: &str, target: &str) -> bool {
        if let Some(row) = self.rows.get_mut(source) {
            row.remove(target).is_some()
        } else {
            false
        }
    }

    pub fn get_mut(&mut self, source: &str, target: &str) -> Option<&mut Connection> {
        self.rows.get_mut(source).and_then(|row| row.get_mut(target))
    }

    pub fn neighbors(&self, source: &str) -> impl Iterator<Item = (&String, &Connection)> {
        self.rows
            .get(source)
            .into_iter()
            .flat_map(|row| row.iter())
    }

    pub fn rows(&self) -> impl Iterator<Item = (&String, &HashMap<String, Connection>)> {
        self.rows.iter()
    }

    pub fn decay_all(&mut self, factor: f64, min_weight: f64) -> usize {
        let mut pruned = 0;
        for row in self.rows.values_mut() {
            row.retain(|_, conn| {
                conn.weight *= factor;
                if conn.weight < min_weight {
                    pruned += 1;
                    false
                } else {
                    true
                }
            });
        }
        self.rows.retain(|_, row| !row.is_empty());
        pruned
    }

    pub fn total_connections(&self) -> usize {
        self.rows.values().map(|row| row.len()).sum()
    }

    /// Hebbian reinforcement: "neurons that fire together, wire together."
    /// If connection exists, strengthen it. Otherwise create a new excitatory one.
    pub fn hebbian_reinforce(
        &mut self,
        source: &str,
        target: &str,
        delta: f64,
        now: u64,
        max_weight: f64,
    ) {
        if let Some(conn) = self.get_mut(source, target) {
            conn.weight = (conn.weight + delta).min(max_weight);
            conn.reinforced_at = now;
        } else {
            self.set(
                source.to_string(),
                target.to_string(),
                Connection {
                    weight: delta.min(max_weight),
                    connection_type: ConnectionType::Excitatory,
                    created_at: now,
                    reinforced_at: now,
                },
            );
        }
    }

    /// Activation spreading: from seed neurons, propagate activation through the network.
    /// Returns (activated_neuron_id, activation_level) pairs above threshold.
    /// Spreads up to `max_hops` times, decaying by `decay_factor` each hop.
    pub fn spread_activation(
        &self,
        seeds: &[(String, f64)],
        threshold: f64,
        max_hops: usize,
        decay_factor: f64,
    ) -> Vec<(String, f64)> {
        let mut activated: HashMap<String, f64> = HashMap::new();

        // Seed initial activations
        for (neuron_id, level) in seeds {
            if *level >= threshold {
                let entry = activated.entry(neuron_id.clone()).or_default();
                *entry = (*entry).max(*level);
            }
        }

        let mut frontier: Vec<(String, f64)> = seeds.to_vec();

        for _hop in 0..max_hops {
            let mut next_frontier = Vec::new();

            for (source_id, source_level) in &frontier {
                for (target_id, conn) in self.neighbors(source_id) {
                    let spread = match conn.connection_type {
                        ConnectionType::Excitatory => source_level * conn.weight * decay_factor,
                        ConnectionType::Inhibitory => -source_level * conn.weight * decay_factor,
                    };

                    let current = activated.entry(target_id.clone()).or_default();
                    let new_level = *current + spread;

                    if new_level >= threshold && *current < threshold {
                        next_frontier.push((target_id.clone(), new_level));
                    }
                    *current = new_level;
                }
            }

            if next_frontier.is_empty() {
                break;
            }
            frontier = next_frontier;
        }

        // Filter to only those above threshold
        activated
            .into_iter()
            .filter(|(_, level)| *level >= threshold)
            .collect()
    }

    /// Pattern separation: given a set of feature neuron IDs, find the closest existing
    /// neuron group (by Jaccard overlap) and return its overlap score.
    /// Used by hippocampus to decide whether to reuse existing connections or create new ones.
    pub fn find_overlapping_group(
        &self,
        features: &[String],
    ) -> Option<(String, f64)> {
        let feature_set: HashSet<&str> = features.iter().map(|s| s.as_str()).collect();
        let mut best: Option<(String, f64)> = None;

        for neuron_id in self.rows.keys() {
            let neighbors: HashSet<&str> = self
                .neighbors(neuron_id)
                .map(|(id, _)| id.as_str())
                .collect();

            if neighbors.is_empty() || feature_set.is_empty() {
                continue;
            }

            let intersection = feature_set.intersection(&neighbors).count();
            let union = feature_set.union(&neighbors).count();
            let jaccard = intersection as f64 / union as f64;

            if jaccard > 0.0 && best.as_ref().map_or(true, |(_, best_j)| jaccard > *best_j) {
                best = Some((neuron_id.clone(), jaccard));
            }
        }

        best
    }
}

impl Default for SparseMatrix {
    fn default() -> Self {
        Self::new()
    }
}
