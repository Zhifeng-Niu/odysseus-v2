defmodule Odysseus.Hippocampus.Nif do
  @moduledoc """
  Hippocampus NIF — holds Rust memory store resource, processes signals, loads NIF.

  Rust NIF functions (loaded from libodysseus_hippocampus):
    new_store/0, store/3, recall/3, consolidate/2, tick_decay/1, stats/1

  v2 algorithms: pattern separation, pattern completion, activation spreading recall.
  """

  use GenServer

  @on_load :load_nifs

  defstruct [:store]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def store, do: GenServer.call(__MODULE__, :get_store)

  # ─── NIF Loading ─────────────────────────────────────────────

  def load_nifs do
    case :code.priv_dir(:odysseus_brain) do
      {:error, _} -> :ok
      priv ->
        path = Path.join([to_string(priv), "libodysseus_hippocampus"])
        :erlang.load_nif(String.to_charlist(path), 0)
    end
  end

  # NIF function stubs (replaced when .dylib loads)
  def new_store, do: :erlang.nif_error("hippocampus NIF not loaded")
  def store(_res, _exp, _now), do: :erlang.nif_error("hippocampus NIF not loaded")
  def recall(_res, _cue, _now), do: :erlang.nif_error("hippocampus NIF not loaded")
  def consolidate(_res, _now), do: :erlang.nif_error("hippocampus NIF not loaded")
  def tick_decay(_res), do: :erlang.nif_error("hippocampus NIF not loaded")
  def stats(_res), do: :erlang.nif_error("hippocampus NIF not loaded")

  # ─── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    Odysseus.WhiteMatter.subscribe(:hippocampus)

    store = try do
      new_store()
    rescue
      _ -> nil
    end

    schedule_decay()
    {:ok, %__MODULE__{store: store}}
  end

  @impl true
  def handle_call(:get_store, _from, state) do
    {:reply, state.store, state}
  end

  # TaggedExperience from amygdala+cortex (encoding pathway)
  @impl true
  def handle_info(%{content: content, emotional_weight: weight, context: ctx, timestamp: ts} = exp, state) do
    handle_tagged_experience(exp, state)
  end

  # Recall request from cortex or other structures
  @impl true
  def handle_info({:recall_request, cues: cues, reply_to: reply_to}, state) do
    now = System.system_time(:millisecond)
    result = if state.store do
      Enum.flat_map(cues, fn cue ->
        try do
          recall(state.store, cue, now)
        rescue
          _ -> []
        end
      end)
    else
      []
    end
    send(reply_to, {:recall_result, result})
    {:noreply, state}
  end

  # Consolidation trigger from hypothalamus or periodic
  @impl true
  def handle_info(%{type: :consolidate, mode: mode}, state) do
    if state.store do
      now = System.system_time(:millisecond)
      try do
        report = consolidate(state.store, now)

        # Forward weight updates to neuron layer
        if Map.get(report, :updates) do
          Enum.each(report.updates, fn update ->
            Odysseus.WhiteMatter.send_signal(:neurons, %{
              type: :weight_update,
              source_neurons: update.source_neurons,
              target_neurons: update.target_neurons,
              delta_weights: update.delta_weights,
              consolidation_score: update.consolidation_score
            })
          end)
        end

        # Notify glymphatic about consolidation activity
        consolidated = Map.get(report, :consolidated, 0)
        reinforced = Map.get(report, :reinforced, 0)
        if consolidated + reinforced > 0 do
          Odysseus.WhiteMatter.send_signal(:glymphatic, %{type: :consolidated, count: consolidated + reinforced})
        end
      rescue
        _ -> :ok
      end
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(:consolidate, state) do
    handle_info(%{type: :consolidate, mode: :light}, state)
  end

  # Periodic decay tick
  @impl true
  def handle_info(:tick_decay, state) do
    if state.store do
      try do
        tick_decay(state.store)
      rescue
        _ -> :ok
      end
    end
    schedule_decay()
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ─── Private ─────────────────────────────────────────────────

  defp handle_tagged_experience(exp, state) do
    if state.store do
      try do
        case store(state.store, exp, exp.timestamp) do
          memory_id when is_binary(memory_id) ->
            # High emotional weight → immediate consolidation
            if exp.emotional_weight > 0.7 do
              consolidate(state.store, exp.timestamp)
            end

            Odysseus.WhiteMatter.send_signal(:neurons, %{
              type: :weight_update,
              memory_id: memory_id,
              emotional_weight: exp.emotional_weight,
              context: exp.context
            })
          _ -> :ok
        end
      rescue
        _ -> :ok
      end
    end
    {:noreply, state}
  end

  defp schedule_decay do
    Process.send_after(self(), :tick_decay, 60_000)
  end
end
