defmodule Odysseus.Temporal do
  @moduledoc """
  Temporal Lobe — language understanding, pattern matching, memory retrieval triggers.

  Converts input into recall cues for hippocampus.
  Pattern matching is deterministic; LLM-assisted understanding via TypeScript bridge.
  """

  use GenServer

  defstruct [
    pattern_cache: %{},
    recall_count: 0
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ─── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    Odysseus.WhiteMatter.subscribe(:temporal)
    {:ok, %__MODULE__{}}
  end

  # Handle error signals and language patterns
  @impl true
  def handle_info(%{target_lobe: :temporal, content: content, attention_weight: weight}, state) do
    # Extract key phrases as recall cues
    cues = extract_recall_cues(content)

    if length(cues) > 0 and weight > 0.3 do
      # Trigger hippocampus recall via white matter
      Odysseus.WhiteMatter.send_signal(:hippocampus, %{
        type: :recall_request,
        cues: cues,
        reply_to: self()
      })
    end

    {:noreply, %{state | recall_count: state.recall_count + length(cues)}}
  end

  # Handle recall results from hippocampus
  @impl true
  def handle_info({:recall_result, results}, state) do
    # Forward recalled memories to frontal lobe for reasoning context
    if length(results) > 0 do
      Odysseus.WhiteMatter.send_signal(:frontal_left, %{
        type: :recalled_memories,
        memories: results,
        count: length(results)
      })
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ─── Cue extraction ──────────────────────────────────────────

  defp extract_recall_cues(content) do
    content
    |> String.split(~r/[,\.\?\!\;\:\s]+/, trim: true)
    |> Enum.filter(&(String.length(&1) > 3))
    |> Enum.take(5)
  end
end
