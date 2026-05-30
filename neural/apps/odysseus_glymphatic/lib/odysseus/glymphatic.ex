defmodule Odysseus.Glymphatic do
  @moduledoc """
  Glymphatic system — idle-period cleanup, weight pruning, connection reclamation.

  Activates during SLEEP state to decay weights, prune connections,
  consolidate memories, and compress narrative.

  Triggers NIF operations on: neurons (tick_decay), hippocampus (consolidate + tick_decay)
  """

  use GenServer

  @cleanup_interval_ms 60_000

  defstruct [:cleaning?, :last_cleanup_at]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Force an immediate cleanup cycle."
  def force_cleanup, do: GenServer.cast(__MODULE__, :force_cleanup)

  @doc "Get cleanup status."
  def status, do: GenServer.call(__MODULE__, :status)

  # ─── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    Odysseus.WhiteMatter.subscribe(:glymphatic)
    schedule_cleanup()
    {:ok, %__MODULE__{cleaning?: false, last_cleanup_at: 0}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{cleaning: state.cleaning?, last_cleanup_at: state.last_cleanup_at}, state}
  end

  @impl true
  def handle_info(:cleanup, state) do
    hypo_state = Odysseus.Hypothalamus.state()
    new_state = if hypo_state == :sleep do
      run_cleanup()
      %{state | cleaning?: true, last_cleanup_at: System.system_time(:millisecond)}
    else
      # Light maintenance during IDLE
      if hypo_state == :idle do
        run_light_maintenance()
      end
      %{state | cleaning?: false}
    end
    schedule_cleanup()
    {:noreply, new_state}
  end

  @impl true
  def handle_cast(:force_cleanup, state) do
    run_cleanup()
    {:noreply, %{state | cleaning?: true, last_cleanup_at: System.system_time(:millisecond)}}
  end

  # Handle consolidation count feedback + catch-all
  @impl true
  def handle_info({:consolidated, _count}, state), do: {:noreply, state}

  # Handle cleanup requests from hypothalamus (resource pressure or state transition)
  @impl true
  def handle_info(%{type: :cleanup, mode: mode}, state) do
    case mode do
      :full ->
        run_cleanup()
        {:noreply, %{state | cleaning?: true, last_cleanup_at: System.system_time(:millisecond)}}
      :partial ->
        run_light_maintenance()
        {:noreply, %{state | cleaning?: false}}
      _ ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ─── Cleanup operations ──────────────────────────────────────

  defp run_cleanup do
    # Full cleanup during SLEEP state

    # 1. Neuron weight decay (prune weak connections)
    send(Odysseus.Neurons.Nif, :tick_decay)

    # 2. Hippocampus consolidation + decay
    send(Odysseus.Hippocampus.Nif, :consolidate)
    send(Odysseus.Hippocampus.Nif, :tick_decay)

    # 3. Clear astrocyte cache (release "glycogen")
    Odysseus.Astrocyte.flush_cache()
  end

  defp run_light_maintenance do
    # Light maintenance during IDLE — only decay, no consolidation
    send(Odysseus.Neurons.Nif, :tick_decay)
    send(Odysseus.Hippocampus.Nif, :tick_decay)
  end

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end
end
