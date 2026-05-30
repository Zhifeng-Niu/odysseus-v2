use rustler::{Env, ResourceArc};
use std::collections::HashMap;
use std::sync::RwLock;

// ─── LRU Cache Entry ─────────────────────────────────────────

struct CacheEntry {
    content: String,
    emotional_weight: f64,
    context: Vec<String>,
    access_count: u64,
    last_accessed: u64,
    inserted_at: u64,
}

// ─── Astrocyte Inner ─────────────────────────────────────────

struct AstrocyteInner {
    /// LRU cache: key → entry, ordered by access recency
    cache: HashMap<String, CacheEntry>,
    /// Access order tracking (most recent at the end)
    access_order: Vec<String>,
    /// Maximum cache entries
    capacity: usize,
    /// Total entries evicted (for metrics)
    evictions: u64,
    /// Cache hits
    hits: u64,
    /// Cache misses
    misses: u64,
}

pub struct AstrocyteRes {
    inner: RwLock<AstrocyteInner>,
}

// ─── NIF functions ───────────────────────────────────────────

#[rustler::nif]
fn new_cache(capacity: usize) -> ResourceArc<AstrocyteRes> {
    ResourceArc::new(AstrocyteRes {
        inner: RwLock::new(AstrocyteInner {
            cache: HashMap::new(),
            access_order: Vec::new(),
            capacity: if capacity == 0 { 1000 } else { capacity },
            evictions: 0,
            hits: 0,
            misses: 0,
        }),
    })
}

/// Store a hot memory entry in the LRU cache.
#[rustler::nif]
fn put(
    res: ResourceArc<AstrocyteRes>,
    key: String,
    content: String,
    emotional_weight: f64,
    context: Vec<String>,
    now: u64,
) -> bool {
    let mut inner = res.inner.write().unwrap();

    // If key exists, update in place
    if let Some(entry) = inner.cache.get_mut(&key) {
        entry.content = content;
        entry.emotional_weight = emotional_weight;
        entry.context = context;
        entry.last_accessed = now;
        entry.access_count += 1;
        touch_access_order(&mut inner.access_order, &key);
        return true;
    }

    // Evict LRU if at capacity
    if inner.cache.len() >= inner.capacity {
        evict_lru(&mut inner);
    }

    inner.cache.insert(
        key.clone(),
        CacheEntry {
            content,
            emotional_weight,
            context,
            access_count: 1,
            last_accessed: now,
            inserted_at: now,
        },
    );
    inner.access_order.push(key);
    true
}

/// Retrieve a cached entry. Returns None on miss.
#[rustler::nif]
fn get(res: ResourceArc<AstrocyteRes>, key: String, now: u64) -> Option<CacheEntryResult> {
    let mut inner = res.inner.write().unwrap();

    // Step 1: Clone data out of cache, then drop the borrow
    let (found, is_hit) = {
        match inner.cache.get_mut(&key) {
            Some(entry) => {
                entry.access_count += 1;
                entry.last_accessed = now;
                (
                    Some((
                        entry.content.clone(),
                        entry.emotional_weight,
                        entry.context.clone(),
                        entry.access_count,
                    )),
                    true,
                )
            }
            None => (None, false),
        }
    };

    // Step 2: Update stats and access order (no active cache borrow)
    if is_hit {
        inner.hits += 1;
        touch_access_order(&mut inner.access_order, &key);
    } else {
        inner.misses += 1;
    }

    found.map(|(content, emotional_weight, context, access_count)| CacheEntryResult {
        content,
        emotional_weight,
        context,
        access_count,
    })
}

/// Release cache entries (triggered by hypothalamus when tokenBudget < 20%).
/// Drops entries with lowest emotional weight first. Returns count released.
#[rustler::nif]
fn release(res: ResourceArc<AstrocyteRes>, fraction: f64) -> usize {
    let mut inner = res.inner.write().unwrap();
    let to_release = ((inner.cache.len() as f64) * fraction.clamp(0.0, 1.0)) as usize;
    if to_release == 0 {
        return 0;
    }

    // Sort keys by emotional weight ascending (evict least important first)
    let mut entries: Vec<(String, f64)> = inner
        .cache
        .iter()
        .map(|(k, v)| (k.clone(), v.emotional_weight))
        .collect();
    entries.sort_by(|a, b| a.1.partial_cmp(&b.1).unwrap());

    let mut released = 0;
    for (key, _) in entries.iter().take(to_release) {
        inner.cache.remove(key);
        inner.access_order.retain(|k| k != key);
        inner.evictions += 1;
        released += 1;
    }

    released
}

/// Clear all cache entries. Returns count cleared.
#[rustler::nif]
fn flush(res: ResourceArc<AstrocyteRes>) -> usize {
    let mut inner = res.inner.write().unwrap();
    let count = inner.cache.len();
    let evicted = count as u64;
    inner.cache.clear();
    inner.access_order.clear();
    inner.evictions += evicted;
    count
}

/// Get cache statistics.
#[rustler::nif]
fn stats(res: ResourceArc<AstrocyteRes>) -> AstrocyteStats {
    let inner = res.inner.read().unwrap();
    let hit_rate = if inner.hits + inner.misses > 0 {
        inner.hits as f64 / (inner.hits + inner.misses) as f64
    } else {
        0.0
    };
    AstrocyteStats {
        entries: inner.cache.len(),
        capacity: inner.capacity,
        hits: inner.hits,
        misses: inner.misses,
        hit_rate,
        evictions: inner.evictions,
    }
}

// ─── NIF result types ────────────────────────────────────────

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "Odysseus.Astrocyte.CacheEntry"]
pub struct CacheEntryResult {
    pub content: String,
    pub emotional_weight: f64,
    pub context: Vec<String>,
    pub access_count: u64,
}

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "Odysseus.Astrocyte.Stats"]
pub struct AstrocyteStats {
    pub entries: usize,
    pub capacity: usize,
    pub hits: u64,
    pub misses: u64,
    pub hit_rate: f64,
    pub evictions: u64,
}

// ─── Helpers ─────────────────────────────────────────────────

fn touch_access_order(order: &mut Vec<String>, key: &str) {
    order.retain(|k| k != key);
    order.push(key.to_string());
}

fn evict_lru(inner: &mut AstrocyteInner) {
    if let Some(lru_key) = inner.access_order.first().cloned() {
        inner.cache.remove(&lru_key);
        inner.access_order.remove(0);
        inner.evictions += 1;
    }
}

// ─── Module registration ─────────────────────────────────────

fn load(env: Env, _term: rustler::Term) -> bool {
    rustler::resource!(AstrocyteRes, env);
    true
}

rustler::init!(
    "Elixir.Odysseus.Astrocyte.Nif",
    [new_cache, put, get, release, flush, stats],
    load = load
);
