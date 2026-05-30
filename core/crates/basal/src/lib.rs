use rustler::{Env, ResourceArc};
use signal_types::ActionCandidate;
use std::collections::HashMap;
use std::sync::RwLock;

// ─── Internal types ──────────────────────────────────────────

struct ExecutionRecord {
    action: String,
    reward: f64,
}

/// 5-level action hierarchy (design doc §八 Basal Ganglia)
#[derive(Debug, Clone, Copy, PartialEq)]
enum ActionLevel {
    /// Level 0: Tool primitives (built-in, like spinal reflexes)
    Primitive = 0,
    /// Level 1: Simple actions (learned from experience)
    Simple = 1,
    /// Level 2: Compound skills (action composition)
    Compound = 2,
    /// Level 3: Workflows (skill orchestration)
    Workflow = 3,
    /// Level 4: Project-level capabilities (workflow composition)
    Project = 4,
}

struct HabitEntry {
    confidence: f64,
    execution_count: u64,
    last_used: u64,
    level: ActionLevel,
}

/// Internal motor program storage (trigger is String, not serde_json::Value)
struct InternalMotorProgram {
    name: String,
    trigger: String,
    steps: Vec<String>,
    confidence: f64,
    execution_count: u64,
    last_used: u64,
}

struct GangliaInner {
    habits: HashMap<String, HabitEntry>,
    motor_programs: HashMap<String, InternalMotorProgram>,
    execution_history: Vec<ExecutionRecord>,
    habit_threshold: f64,
}

pub struct GangliaRes {
    inner: RwLock<GangliaInner>,
}

// ─── NIF functions ───────────────────────────────────────────

#[rustler::nif]
fn new_ganglia() -> ResourceArc<GangliaRes> {
    ResourceArc::new(GangliaRes {
        inner: RwLock::new(GangliaInner {
            habits: HashMap::new(),
            motor_programs: HashMap::new(),
            execution_history: Vec::new(),
            habit_threshold: 0.7,
        }),
    })
}

/// Action selection with habit boosting and level-based routing.
/// Habits with high confidence bypass frontal lobe reasoning entirely.
#[rustler::nif]
fn select_action(
    res: ResourceArc<GangliaRes>,
    candidates: Vec<ActionCandidate>,
) -> Option<ActionCandidate> {
    let inner = res.inner.read().unwrap();

    // Check if any candidate is a well-formed habit (fast path, no LLM needed)
    for candidate in &candidates {
        if let Some(habit) = inner.habits.get(&candidate.action) {
            if habit.confidence >= inner.habit_threshold {
                let mut boosted = candidate.clone();
                boosted.expected_reward =
                    (candidate.expected_reward * 0.3) + (habit.confidence * 0.7);
                boosted.confidence = habit.confidence;
                return Some(boosted);
            }
        }
    }

    // No habit match — select by expected reward × confidence × (1 - risk)
    candidates
        .iter()
        .max_by(|a, b| {
            let sa = a.expected_reward * a.confidence * (1.0 - a.risk_level);
            let sb = b.expected_reward * b.confidence * (1.0 - b.risk_level);
            sa.partial_cmp(&sb).unwrap_or(std::cmp::Ordering::Equal)
        })
        .cloned()
}

/// Record execution outcome. Strengthens habits for repeated successful actions.
/// Implements dopamine-based learning: above expectation → reinforce, below → weaken.
#[rustler::nif]
fn record_execution(
    res: ResourceArc<GangliaRes>,
    action: String,
    reward: f64,
    now: u64,
) -> bool {
    let mut inner = res.inner.write().unwrap();

    inner.execution_history.push(ExecutionRecord {
        action: action.clone(),
        reward,
    });
    if inner.execution_history.len() > 100 {
        inner.execution_history.remove(0);
    }

    let count = inner
        .execution_history
        .iter()
        .filter(|r| r.action == action)
        .count();

    if count >= 3 {
        let avg_reward: f64 = inner
            .execution_history
            .iter()
            .filter(|r| r.action == action)
            .map(|r| r.reward)
            .sum::<f64>()
            / count as f64;

        let confidence = (count as f64 / 10.0).min(1.0) * avg_reward;

        // Determine action level from existing motor program or default
        let level = inner
            .motor_programs
            .get(&action)
            .map(|mp| classify_level(mp.steps.len()))
            .unwrap_or(ActionLevel::Simple);

        if confidence >= inner.habit_threshold {
            inner.habits.insert(
                action,
                HabitEntry {
                    confidence,
                    execution_count: count as u64,
                    last_used: now,
                    level,
                },
            );
        }
    }

    true
}

/// Register a motor program (action template with steps).
#[rustler::nif]
fn register_program(
    res: ResourceArc<GangliaRes>,
    name: String,
    trigger: String,
    steps: Vec<String>,
    confidence: f64,
    now: u64,
) -> String {
    let mut inner = res.inner.write().unwrap();
    let program = InternalMotorProgram {
        name: name.clone(),
        trigger,
        steps,
        confidence,
        execution_count: 0,
        last_used: now,
    };
    inner.motor_programs.insert(name.clone(), program);
    name
}

/// Get a motor program by name.
#[rustler::nif]
fn get_program(
    res: ResourceArc<GangliaRes>,
    name: String,
) -> Option<MotorProgramEntry> {
    let inner = res.inner.read().unwrap();
    inner.motor_programs.get(&name).map(|mp| MotorProgramEntry {
        name: mp.name.clone(),
        confidence: mp.confidence,
        execution_count: mp.execution_count,
        step_count: mp.steps.len(),
    })
}

/// List all motor programs, optionally filtered by minimum confidence.
#[rustler::nif]
fn list_programs(res: ResourceArc<GangliaRes>) -> Vec<MotorProgramEntry> {
    let inner = res.inner.read().unwrap();
    inner
        .motor_programs
        .values()
        .map(|mp| MotorProgramEntry {
            name: mp.name.clone(),
            confidence: mp.confidence,
            execution_count: mp.execution_count,
            step_count: mp.steps.len(),
        })
        .collect()
}

/// Check if an action is habitual (can skip LLM reasoning).
#[rustler::nif]
fn is_habit(res: ResourceArc<GangliaRes>, action: String) -> bool {
    res.inner
        .read()
        .unwrap()
        .habits
        .get(&action)
        .map(|h| h.confidence >= 0.7)
        .unwrap_or(false)
}

/// Get habit count and motor program count.
#[rustler::nif]
fn stats(res: ResourceArc<GangliaRes>) -> GangliaStats {
    let inner = res.inner.read().unwrap();
    let habit_count = inner.habits.len();
    let program_count = inner.motor_programs.len();

    let mut level_counts = [0usize; 5];
    for habit in inner.habits.values() {
        level_counts[habit.level as usize] += 1;
    }

    GangliaStats {
        habits: habit_count,
        motor_programs: program_count,
        level_0_primitives: level_counts[0],
        level_1_simple: level_counts[1],
        level_2_compound: level_counts[2],
        level_3_workflows: level_counts[3],
        level_4_project: level_counts[4],
    }
}

// ─── Helpers ─────────────────────────────────────────────────

fn classify_level(step_count: usize) -> ActionLevel {
    match step_count {
        0..=1 => ActionLevel::Primitive,
        2..=3 => ActionLevel::Simple,
        4..=6 => ActionLevel::Compound,
        7..=12 => ActionLevel::Workflow,
        _ => ActionLevel::Project,
    }
}

// ─── NIF result types ────────────────────────────────────────

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "Odysseus.Basal.MotorProgramEntry"]
pub struct MotorProgramEntry {
    pub name: String,
    pub confidence: f64,
    pub execution_count: u64,
    pub step_count: usize,
}

#[derive(Debug, Clone, rustler::NifStruct)]
#[module = "Odysseus.Basal.GangliaStats"]
pub struct GangliaStats {
    pub habits: usize,
    pub motor_programs: usize,
    pub level_0_primitives: usize,
    pub level_1_simple: usize,
    pub level_2_compound: usize,
    pub level_3_workflows: usize,
    pub level_4_project: usize,
}

// ─── Module registration ─────────────────────────────────────

fn load(env: Env, _term: rustler::Term) -> bool {
    rustler::resource!(GangliaRes, env);
    true
}

rustler::init!(
    "Elixir.Odysseus.Basal.Nif",
    [
        new_ganglia,
        select_action,
        record_execution,
        register_program,
        get_program,
        list_programs,
        is_habit,
        stats,
    ],
    load = load
);
