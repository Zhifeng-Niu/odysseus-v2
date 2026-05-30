defmodule Odysseus.Hypothalamus do
  @moduledoc """
  Hypothalamus — resource management, homeostasis, and state machine.

  Monitors: tokenBudget (blood sugar), computeLoad (temperature),
  memoryPressure (hunger), interactionGap (circadian rhythm).

  State machine:
    ACTIVE ──(5min idle)──→ IDLE ──(30min idle)──→ SLEEP
    SLEEP/IDLE ──(input)──→ ACTIVE

  Homeostasis:
    tokenBudget < 20%    → astrocyte cache release
    computeLoad > 80%    → suppress non-essential activity
    memoryPressure > 75% → trigger glymphatic cleanup
    interactionGap > 5min → idle mode
    interactionGap > 30min → sleep mode (deep consolidation)
  """

  use GenServer, restart: :permanent

  @idle_threshold_ms 5 * 60 * 1000
  @sleep_threshold_ms 30 * 60 * 1000
  @monitor_interval_ms 10_000

  # Homeostasis thresholds
  @token_budget_critical 0.2
  @compute_load_high 0.8
  @memory_pressure_high 0.75

  defstruct [
    state: :active,
    token_budget: 1.0,
    compute_load: 0.0,
    memory_pressure: 0.0,
    last_interaction_at: 0,
    total_tokens_used: 0,
    cleanup_count: 0
  ]

  # ─── Public API ──────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def state, do: GenServer.call(__MODULE__, :get_state)
  def metrics, do: GenServer.call(__MODULE__, :metrics)
  def report_interaction, do: GenServer.cast(__MODULE__, :interaction)
  def update_metrics(opts), do: GenServer.cast(__MODULE__, {:update, opts})

  def consume_tokens(amount) when is_number(amount) and amount > 0 do
    GenServer.cast(__MODULE__, {:consume_tokens, amount})
  end

  # ─── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    Odysseus.WhiteMatter.subscribe(:hypothalamus)
    schedule_monitor()
    {:ok, %__MODULE__{last_interaction_at: System.system_time(:millisecond)}}
  end

  @impl true
  def handle_call(:get_state, _from, data), do: {:reply, data.state, data}
  def handle_call(:metrics, _from, data), do: {:reply, Map.from_struct(data), data}

  @impl true
  def handle_cast(:interaction, data) do
    now = System.system_time(:millisecond)
    prev_state = data.state
    new_state = if prev_state != :active, do: :active, else: prev_state

    if new_state != prev_state do
      broadcast_brain_state(new_state)
    end

    {:noreply, %{data | state: new_state, last_interaction_at: now}}
  end

  @impl true
  def handle_cast({:update, opts}, data) do
    new_data = Enum.reduce(opts, data, fn {k, v}, acc ->
      if Map.has_key?(acc, k), do: Map.put(acc, k, v), else: acc
    end)
    {:noreply, new_data}
  end

  @impl true
  def handle_cast({:consume_tokens, amount}, data) do
    new_budget = max(0.0, data.token_budget - amount / 100_000.0)
    new_total = data.total_tokens_used + amount
    {:noreply, %{data | token_budget: new_budget, total_tokens_used: new_total}}
  end

  @impl true
  def handle_info(:monitor, data) do
    gap = System.system_time(:millisecond) - data.last_interaction_at

    new_state = cond do
      gap > @sleep_threshold_ms -> :sleep
      gap > @idle_threshold_ms -> :idle
      true -> data.state
    end

    # Broadcast state transitions
    if new_state != data.state do
      broadcast_brain_state(new_state)
    end

    # Homeostasis actions
    data = run_homeostasis(data)

    schedule_monitor()
    {:noreply, %{data | state: new_state}}
  end

  # ─── Homeostasis ─────────────────────────────────────────────

  defp run_homeostasis(data) do
    data
    |> check_token_budget()
    |> check_compute_load()
    |> check_memory_pressure()
    |> check_idle_consolidation()
  end

  # tokenBudget < 20% → astrocyte cache release
  defp check_token_budget(%{token_budget: budget} = data) when budget < @token_budget_critical do
    Odysseus.WhiteMatter.send_signal(:astrocyte, %{type: :cache_release, fraction: 0.3})
    data
  end
  defp check_token_budget(data), do: data

  # computeLoad > 80% → suppress non-essential, broadcast throttle signal
  defp check_compute_load(%{compute_load: load} = data) when load > @compute_load_high do
    Odysseus.WhiteMatter.send_signal(:thalamus, %{type: :throttle, level: :high})
    data
  end
  defp check_compute_load(data), do: data

  # memoryPressure > 75% → trigger glymphatic cleanup
  defp check_memory_pressure(%{memory_pressure: pressure} = data) when pressure > @memory_pressure_high do
    Odysseus.WhiteMatter.send_signal(:glymphatic, %{type: :cleanup, mode: :partial})
    %{data | cleanup_count: data.cleanup_count + 1}
  end
  defp check_memory_pressure(data), do: data

  # Idle/Sleep → light/deep consolidation
  defp check_idle_consolidation(%{state: :idle} = data) do
    Odysseus.WhiteMatter.send_signal(:hippocampus, %{type: :consolidate, mode: :light})
    data
  end
  defp check_idle_consolidation(%{state: :sleep} = data) do
    Odysseus.WhiteMatter.send_signal(:hippocampus, %{type: :consolidate, mode: :deep})
    Odysseus.WhiteMatter.send_signal(:glymphatic, %{type: :cleanup, mode: :full})
    data
  end
  defp check_idle_consolidation(data), do: data

  # ─── Helpers ─────────────────────────────────────────────────

  defp broadcast_brain_state(new_state) do
    Odysseus.WhiteMatter.broadcast(%{type: :brain_state, state: new_state, source: :hypothalamus})
  end

  defp schedule_monitor do
    Process.send_after(self(), :monitor, @monitor_interval_ms)
  end
end
