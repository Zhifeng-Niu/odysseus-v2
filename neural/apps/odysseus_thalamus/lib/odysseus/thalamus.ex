defmodule Odysseus.Thalamus do
  @moduledoc """
  Thalamus — signal router, attention gate, and fast-path switch.

  Routes SensorySignals from the brainstem to appropriate cortical lobes.
  High-intensity or threat-tagged signals also go to the amygdala (fast path).
  Low-attention signals are gated out (consciousness filter).
  """

  use GenServer

  @attention_threshold 0.15

  defstruct [:attention_threshold, brain_state: :active, attention_weights: %{}]

  # ─── Public API ──────────────────────────────────────────────

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Route a sensory signal."
  def route(signal) do
    GenServer.cast(__MODULE__, {:route, signal})
  end

  # ─── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(opts) do
    threshold = Keyword.get(opts, :attention_threshold, @attention_threshold)
    Odysseus.WhiteMatter.subscribe(:thalamus)
    {:ok, %__MODULE__{attention_threshold: threshold}}
  end

  @impl true
  def handle_cast({:route, signal}, state) do
    # Consciousness gate: block signals during sleep
    if state.brain_state == :sleep do
      {:noreply, state}
    else
      routed = transform(signal)

      # Use updated attention weight if available
      lobe = routed.target_lobe
      weight = Map.get(state.attention_weights, lobe, routed.attention_weight)

      if weight >= state.attention_threshold do
        Odysseus.WhiteMatter.send_signal(lobe, routed)

        # Fast path: high intensity or threat keywords → amygdala simultaneously
        if signal.intensity > 0.8 or has_threat_signal?(signal.raw) do
          Odysseus.WhiteMatter.send_signal(:amygdala, signal)
        end
      end

      {:noreply, state}
    end
  end

  # Attention feedback from parietal lobe
  @impl true
  def handle_info(%{type: :attention_update, weights: weights}, state) do
    {:noreply, %{state | attention_weights: weights}}
  end

  # Brain state change from hypothalamus
  @impl true
  def handle_info(%{type: :brain_state, state: new_state}, state) do
    {:noreply, %{state | brain_state: new_state}}
  end

  # ─── Signal transformation (synapse) ─────────────────────────

  defp transform(%{modality: modality, raw: raw, intensity: intensity, timestamp: ts}) do
    %{
      target_lobe: route_target(modality, intensity),
      content: raw,
      modality: Atom.to_string(modality),
      attention_weight: intensity,
      priority: compute_priority(intensity),
      timestamp: ts
    }
  end

  defp route_target(:text, intensity) when intensity > 0.7, do: :frontal_left
  defp route_target(:text, _), do: :frontal_right
  defp route_target(:command, _), do: :parietal
  defp route_target(:event, _), do: :occipital
  defp route_target(:error, _), do: :temporal
  defp route_target(_, _), do: :frontal_left

  defp compute_priority(intensity) when intensity > 0.9, do: :critical
  defp compute_priority(intensity) when intensity > 0.7, do: :high
  defp compute_priority(intensity) when intensity > 0.3, do: :normal
  defp compute_priority(_), do: :low

  defp has_threat_signal?(raw) when is_binary(raw) do
    threat_words = ["error", "fail", "crash", "bug", "wrong", "broken", "critical", "urgent", "alert"]
    String.downcase(raw) |> String.contains?(threat_words)
  end
  defp has_threat_signal?(_), do: false
end
