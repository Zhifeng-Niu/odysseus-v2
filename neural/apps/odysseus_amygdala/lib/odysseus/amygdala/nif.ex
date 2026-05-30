defmodule Odysseus.Amygdala.Nif do
  @moduledoc """
  Amygdala NIF — holds Rust emotional state resource, fast emotional evaluation.

  Rust NIF functions (loaded from libodysseus_amygdala.dylib):
    new_state/0, evaluate/2, state_summary/1
  """

  use GenServer

  @on_load :load_nifs

  defstruct [:state_res]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Evaluate emotional content of text using NIF. Returns tag map or nil."
  def evaluate_text(text) do
    GenServer.call(__MODULE__, {:evaluate, text})
  end

  # ─── NIF Loading ─────────────────────────────────────────────

  def load_nifs do
    case :code.priv_dir(:odysseus_brain) do
      {:error, _} -> :ok
      priv ->
        path = Path.join([to_string(priv), "libodysseus_amygdala"])
        :erlang.load_nif(String.to_charlist(path), 0)
    end
  end

  def new_state, do: :erlang.nif_error("amygdala NIF not loaded")
  def evaluate(_res, _text), do: :erlang.nif_error("amygdala NIF not loaded")
  def state_summary(_res), do: :erlang.nif_error("amygdala NIF not loaded")

  # ─── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    Odysseus.WhiteMatter.subscribe(:amygdala)
    state_res = safe_call(fn -> new_state() end, nil)
    {:ok, %__MODULE__{state_res: state_res}}
  end

  @impl true
  def handle_call({:evaluate, text}, _from, state) do
    result = if state.state_res do
      safe_call(fn -> evaluate(state.state_res, text) end, nil)
    else
      nil
    end
    {:reply, result, state}
  end

  @impl true
  def handle_info(%{raw: raw, intensity: intensity, modality: modality}, state) do
    if state.state_res do
      safe_call(fn ->
        tag = evaluate(state.state_res, raw)
        Odysseus.WhiteMatter.send_signal(:hippocampus, %{
          content: raw,
          emotional_weight: tag.threat + tag.opportunity,
          valence: tag.valence, arousal: tag.arousal,
          context: [Atom.to_string(modality)],
          timestamp: System.system_time(:millisecond)
        })
        if intensity > 0.8 do
          Odysseus.WhiteMatter.send_signal(:frontal_left, %{
            type: :emotional_tag, valence: tag.valence, threat: tag.threat,
            opportunity: tag.opportunity, urgency: tag.urgency
          })
        end
        if tag.threat > 0.9 do
          Odysseus.WhiteMatter.send_signal(:brainstem, %{type: :emergency, threat: tag.threat, source: raw})
        end
      end, :ok)
    end
    {:noreply, state}
  end

  @impl true
  def handle_info({:query_state, reply_to}, state) do
    result = if state.state_res, do: safe_call(fn -> state_summary(state.state_res) end, {0.0, 0.5, 0.0, 0.0}), else: {0.0, 0.5, 0.0, 0.0}
    send(reply_to, {:emotional_state, result})
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
