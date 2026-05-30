defmodule Odysseus.Parietal do
  @moduledoc """
  Parietal Lobe — attention allocation, spatial context, input integration.

  Deterministic computation (no LLM). Manages attention weights and
  feeds them back to thalamus for signal gating adjustments.
  """

  use GenServer

  defstruct [
    attention_map: %{},
    focus_stack: [],
    total_attention: 1.0
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Get current attention allocation."
  def attention, do: GenServer.call(__MODULE__, :attention)

  # ─── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    Odysseus.WhiteMatter.subscribe(:parietal)
    {:ok, %__MODULE__{attention_map: %{frontal_left: 0.4, frontal_right: 0.2, temporal: 0.2, occipital: 0.2}}}
  end

  @impl true
  def handle_call(:attention, _from, state) do
    {:reply, state.attention_map, state}
  end

  # Handle command signals — route processing
  @impl true
  def handle_info(%{target_lobe: :parietal, content: _content, attention_weight: weight}, state) do
    new_map = reallocate_attention(state.attention_map, :parietal, weight)

    # Feed attention update back to thalamus
    Odysseus.WhiteMatter.send_signal(:thalamus, %{
      type: :attention_update,
      focus: top_focus(new_map),
      weights: new_map
    })

    {:noreply, %{state | attention_map: new_map}}
  end

  # Handle attention feedback from other lobes
  @impl true
  def handle_info(%{type: :request_focus, region: region, weight: weight}, state) do
    new_map = reallocate_attention(state.attention_map, region, weight)
    {:noreply, %{state | attention_map: new_map}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp reallocate_attention(current, _region, weight) do
    # Shift attention toward the requesting region proportionally
    Map.new(current, fn {k, v} ->
      {k, v * (1.0 - weight * 0.1)}
    end)
  end

  defp top_focus(attention_map) do
    attention_map
    |> Enum.max_by(fn {_k, v} -> v end, fn -> {:none, 0} end)
    |> elem(0)
  end
end
