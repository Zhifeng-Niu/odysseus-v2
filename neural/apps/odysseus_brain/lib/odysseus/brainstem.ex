defmodule Odysseus.Brainstem do
  @moduledoc """
  Brainstem — never-stop loop, sensory channel integration, basic reflexes.

  The brainstem runs a continuous perceive→reason→act→reflect→evolve cycle.
  It converts raw external input into SensorySignals and routes them through
  white matter to the thalamus. Basic reflexes (ping, health, echo) are
  handled here without involving the cortex.

  RAS (Reticular Activating System) controls global arousal:
  - High arousal: emergency mode, all signals high priority
  - Low arousal: energy saving, only critical signals processed
  """

  use GenServer

  defstruct [
    :input_queue,
    arousal_level: 0.5,
    cycle_count: 0,
    last_input_at: 0,
    reflexes: %{}
  ]

  @tick_interval_ms 100
  @reflex_commands ~w(ping health echo help)

  # ─── Public API ──────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Inject a sensory input into the brainstem."
  def inject(source, modality, raw, intensity \\ 0.5) do
    signal = %{
      source: source,
      modality: modality,
      raw: raw,
      intensity: intensity,
      timestamp: System.system_time(:millisecond)
    }
    GenServer.cast(__MODULE__, {:input, signal})
  end

  @doc "Get current arousal level (0.0-1.0)."
  def arousal do
    GenServer.call(__MODULE__, :arousal)
  end

  @doc "Get brainstem status."
  def status do
    GenServer.call(__MODULE__, :status)
  end

  # ─── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    Odysseus.WhiteMatter.subscribe(:brainstem)
    schedule_tick()
    {:ok, %__MODULE__{
      input_queue: :queue.new(),
      arousal_level: 0.5,
      cycle_count: 0,
      last_input_at: System.system_time(:millisecond),
      reflexes: Map.new(@reflex_commands, &{&1, true})
    }}
  end

  @impl true
  def handle_cast({:input, signal}, state) do
    now = System.system_time(:millisecond)
    queue = :queue.in(signal, state.input_queue)
    # Input increases arousal
    arousal = min(1.0, state.arousal_level + signal.intensity * 0.1)
    {:noreply, %{state | input_queue: queue, arousal_level: arousal, last_input_at: now}}
  end

  @impl true
  def handle_call(:arousal, _from, state) do
    {:reply, state.arousal_level, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{
      arousal: state.arousal_level,
      cycle_count: state.cycle_count,
      queue_size: :queue.len(state.input_queue)
    }, state}
  end

  @impl true
  def handle_info(:tick, state) do
    new_state = run_cycle(state)
    schedule_tick()
    {:noreply, new_state}
  end

  # Emergency from amygdala — boost arousal, prioritize
  @impl true
  def handle_info(%{type: :emergency, threat: threat, source: _source}, state) do
    arousal = min(1.0, state.arousal_level + threat * 0.3)
    {:noreply, %{state | arousal_level: arousal}}
  end

  # ─── Never-stop cycle ────────────────────────────────────────

  defp run_cycle(state) do
    case :queue.out(state.input_queue) do
      {{:value, signal}, queue} ->
        process_signal(signal)
        # Decay arousal slightly after processing
        arousal = max(0.1, state.arousal_level * 0.999)
        %{state | input_queue: queue, cycle_count: state.cycle_count + 1, arousal_level: arousal}

      {:empty, _queue} ->
        # No input — decay arousal toward baseline
        gap = System.system_time(:millisecond) - state.last_input_at
        arousal = cond do
          gap > 30_000 -> max(0.1, state.arousal_level * 0.99)  # 30s idle → deeper decay
          gap > 5_000 -> max(0.2, state.arousal_level * 0.999)  # 5s idle → gentle decay
          true -> state.arousal_level
        end
        %{state | arousal_level: arousal, cycle_count: state.cycle_count + 1}
    end
  end

  defp process_signal(signal) do
    # Check for basic reflexes first (no cortex needed)
    if reflex?(signal) do
      handle_reflex(signal)
    else
      # Route through white matter to thalamus
      Odysseus.WhiteMatter.send_signal(:thalamus, signal)
    end
  end

  defp reflex?(%{modality: :command, raw: raw}) do
    cmd = raw |> String.trim() |> String.downcase()
    Map.has_key?(%{ping: true, health: true, echo: true, help: true}, String.to_atom(cmd))
  end
  defp reflex?(_), do: false

  defp handle_reflex(%{raw: raw}) do
    cmd = raw |> String.trim() |> String.downcase() |> String.to_atom()
    response = case cmd do
      :ping -> {:ok, "pong"}
      :health -> {:ok, "all systems nominal"}
      :echo -> {:ok, raw}
      :help -> {:ok, "Available: ping, health, echo, help"}
      _ -> {:unknown, raw}
    end
    Odysseus.WhiteMatter.send_signal(:output, %{reflex: response})
  end

  defp schedule_tick do
    Process.send_after(self(), :tick, @tick_interval_ms)
  end
end
