defmodule Odysseus.Neurons.Nif do
  @moduledoc """
  Neurons NIF — holds Rust neuron layer resource, processes signals.

  Rust NIF functions (loaded from libodysseus_neurons.dylib):
    new_layer/0, recall/2, learn/4, reinforce/3, tick_decay/1,
    save/2, load_layer/2, stats/1
  """

  use GenServer

  @on_load :load_nifs

  defstruct [:layer]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def layer, do: GenServer.call(__MODULE__, :get_layer)

  # ─── NIF Loading ─────────────────────────────────────────────

  def load_nifs do
    case :code.priv_dir(:odysseus_brain) do
      {:error, _} -> :ok
      priv ->
        path = Path.join([to_string(priv), "libodysseus_neurons"])
        :erlang.load_nif(String.to_charlist(path), 0)
    end
  end

  def new_layer, do: :erlang.nif_error("neurons NIF not loaded")
  def recall(_res, _cue), do: :erlang.nif_error("neurons NIF not loaded")
  def learn(_res, _exp, _feat, _now), do: :erlang.nif_error("neurons NIF not loaded")
  def reinforce(_res, _ids, _levels, _now), do: :erlang.nif_error("neurons NIF not loaded")
  def tick_decay(_res), do: :erlang.nif_error("neurons NIF not loaded")
  def save(_res, _path), do: :erlang.nif_error("neurons NIF not loaded")
  def load_layer(_res, _path), do: :erlang.nif_error("neurons NIF not loaded")
  def stats(_res), do: :erlang.nif_error("neurons NIF not loaded")

  # ─── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    Odysseus.WhiteMatter.subscribe(:neurons)
    layer = safe_call(fn -> new_layer() end, nil)
    {:ok, %__MODULE__{layer: layer}}
  end

  @impl true
  def handle_call(:get_layer, _from, state), do: {:reply, state.layer, state}

  @impl true
  def handle_info(%{type: :weight_update, memory_id: id, emotional_weight: weight, context: ctx}, state) do
    if state.layer do
      now = System.system_time(:millisecond)
      features = ctx || [id]
      safe_call(fn ->
        case learn(state.layer, id, features, now) do
          {:ok, neuron_id} when weight > 0.5 ->
            reinforce(state.layer, [neuron_id], [weight], now)
          _ -> :ok
        end
      end, :ok)
    end
    {:noreply, state}
  end

  @impl true
  def handle_info({:recall, cue, reply_to}, state) do
    result = if state.layer, do: safe_call(fn -> recall(state.layer, cue) end, []), else: []
    send(reply_to, {:recall_result, result})
    {:noreply, state}
  end

  @impl true
  def handle_info(:tick_decay, state) do
    if state.layer, do: safe_call(fn -> tick_decay(state.layer) end, :ok)
    {:noreply, state}
  end

  @impl true
  def handle_info({:save, path, reply_to}, state) do
    result = if state.layer, do: safe_call(fn -> save(state.layer, path) end, {:error, :nif}), else: {:error, :no_layer}
    send(reply_to, result)
    {:noreply, state}
  end

  @impl true
  def handle_info({:load_nif, path, reply_to}, state) do
    result = if state.layer, do: safe_call(fn -> load_layer(state.layer, path) end, {false, 0, 0}), else: {false, 0, 0}
    send(reply_to, result)
    {:noreply, state}
  end

  @impl true
  def handle_info({:stats, reply_to}, state) do
    result = if state.layer, do: safe_call(fn -> stats(state.layer) end, {0, 0}), else: {0, 0}
    send(reply_to, {:neuron_stats, result})
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp safe_call(fun, fallback) do
    try do
      fun.()
    rescue
      _ -> fallback
    end
  end
end
