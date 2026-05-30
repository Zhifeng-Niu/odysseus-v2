defmodule Odysseus.FrontalRight do
  @moduledoc """
  Right Frontal Lobe — creative intuition, holistic judgment, big-picture thinking.

  Receives signals via corpus callosum sync from left hemisphere.
  Provides alternative perspectives and creative solutions.
  """

  use GenServer

  defstruct [
    intuition_buffer: [],
    pattern_memory: %{}
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ─── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    Odysseus.WhiteMatter.subscribe(:frontal_right)
    {:ok, %__MODULE__{}}
  end

  # Handle routed signals (lower intensity → intuitive processing)
  @impl true
  def handle_info(%{target_lobe: :frontal_right, content: content, attention_weight: _weight}, state) do
    intuition = generate_intuition(content, state.pattern_memory)

    if intuition != nil do
      Odysseus.WhiteMatter.corpus_callosum(:right, %{
        type: :intuition_result,
        content: content,
        insight: intuition,
        approach: "creative"
      })
    end

    {:noreply, %{state | intuition_buffer: Enum.take([content | state.intuition_buffer], 50)}}
  end

  # Handle left-brain analysis sync
  @impl true
  def handle_info(%{type: :analysis_result, content: _content, candidates: _n, reasoning: "analytical"}, state) do
    # Left brain shared its analysis — generate complementary creative perspective
    {:noreply, state}
  end

  # Handle re-planning requests from left brain (after cerebellum error)
  @impl true
  def handle_info(%{type: :re_plan, error: error, approach: "creative"}, state) do
    # Generate alternative approach when analytical path fails
    alternative = %{
      type: :creative_alternative,
      original_error: error,
      suggestion: "try_different_approach",
      confidence: 0.5
    }
    Odysseus.WhiteMatter.corpus_callosum(:right, alternative)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  defp generate_intuition(content, _patterns) do
    # Try TypeScript LLM bridge, fall back to deterministic
    case call_llm_bridge(:right, content) do
      {:ok, insight} -> insight
      _ -> deterministic_intuition(content)
    end
  end

  defp deterministic_intuition(content) do
    cond do
      String.length(content) < 10 -> nil
      true -> %{insight: "pattern_detected", confidence: 0.6}
    end
  end

  defp call_llm_bridge(hemisphere, content) do
    url = Application.get_env(:odysseus_frontal_right, :llm_bridge_url, "http://localhost:3100")
    path = if hemisphere == :left, do: "/cortex/left", else: "/cortex/right"
    body = Jason.encode!(%{text: content})

    case :httpc.request(:post, {String.to_charlist(url <> path), [], 'application/json', body}, [timeout: 5000], []) do
      {:ok, {{_, 200, _}, _, resp_body}} ->
        case Jason.decode(to_string(resp_body)) do
          {:ok, %{"insight" => insight}} -> {:ok, insight}
          _ -> {:error, :parse_error}
        end
      _ -> {:error, :bridge_unavailable}
    end
  rescue
    _ -> {:error, :bridge_error}
  end
end
