defmodule Odysseus.FrontalLeft do
  @moduledoc """
  Left Frontal Lobe — analytical reasoning, logic, language production.

  Receives RoutedSignal + EmotionalTag + recalled memories from hippocampus.
  Produces ActionCandidate[] → basal ganglia for action selection.
  Coordinates with right frontal lobe via corpus callosum.
  """

  use GenServer

  defstruct [
    :pending_plan,
    active_goals: [],
    decision_history: [],
    context_buffer: []
  ]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def process(signal), do: GenServer.cast(__MODULE__, {:process, signal})
  def goals, do: GenServer.call(__MODULE__, :goals)
  def status, do: GenServer.call(__MODULE__, :status)

  # ─── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    Odysseus.WhiteMatter.subscribe(:frontal_left)
    {:ok, %__MODULE__{}}
  end

  @impl true
  def handle_call(:goals, _from, state) do
    {:reply, state.active_goals, state}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{
      goals: length(state.active_goals),
      decisions: length(state.decision_history),
      pending: state.pending_plan != nil
    }, state}
  end

  # Handle routed signals from thalamus (main reasoning path)
  @impl true
  def handle_info(%{target_lobe: :frontal_left, content: content, attention_weight: weight} = signal, state) do
    # Build context from recent history + emotional state
    context = build_context(state, signal)

    # In production, this would call the LLM via TypeScript bridge.
    # For now, generate action candidates through deterministic rules.
    candidates = generate_candidates(content, context, weight)

    if length(candidates) > 0 do
      Odysseus.WhiteMatter.send_signal(:basal, %{
        type: :select_action,
        candidates: candidates
      })
    end

    # Sync analysis results with right hemisphere
    Odysseus.WhiteMatter.corpus_callosum(:left, %{
      type: :analysis_result,
      content: content,
      candidates: length(candidates),
      reasoning: "analytical"
    })

    {:noreply, update_context(state, signal)}
  end

  # Handle emotional tags from amygdala
  @impl true
  def handle_info(%{type: :emotional_tag, threat: threat, opportunity: opp}, state) do
    # Adjust reasoning based on emotional context
    new_state = cond do
      threat > 0.7 -> %{state | context_buffer: [%{alert: :high_threat, threat: threat} | state.context_buffer]}
      opp > 0.7 -> %{state | context_buffer: [%{alert: :high_opportunity, opportunity: opp} | state.context_buffer]}
      true -> state
    end
    {:noreply, new_state}
  end

  # Handle habit notifications from basal ganglia
  @impl true
  def handle_info(%{type: :habit_formed, action: action}, state) do
    {:noreply, %{state | context_buffer: [%{habit: action} | Enum.take(state.context_buffer, 19)]}}
  end

  # Handle predictions from cerebellum
  @impl true
  def handle_info(%{type: :prediction, action: action, expected_outcome: expected}, state) do
    {:noreply, %{state | context_buffer: [%{prediction: action, expected: expected} | Enum.take(state.context_buffer, 19)]}}
  end

  # Handle error signals from cerebellum
  @impl true
  def handle_info(%{type: :error_signal, magnitude: mag} = error, state) do
    # Large errors trigger re-planning
    if mag > 0.5 do
      Odysseus.WhiteMatter.send_signal(:frontal_right, %{
        type: :re_plan,
        error: error,
        approach: "creative"
      })
    end
    {:noreply, state}
  end

  # Handle right hemisphere sync (corpus callosum)
  @impl true
  def handle_info(%{type: :intuition_result, content: _, approach: "creative"}, state) do
    # Merge right-brain intuition with left-brain analysis
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  # ─── Internal ────────────────────────────────────────────────

  defp build_context(state, signal) do
    %{
      history: Enum.take(state.decision_history, 10),
      emotional: Map.get(signal, :emotional_weight, 0.5),
      attention: Map.get(signal, :attention_weight, 0.5),
      goals: state.active_goals
    }
  end

  defp generate_candidates(content, _context, weight) do
    # Try TypeScript LLM bridge first, fall back to deterministic rules
    case call_llm_bridge(:left, content) do
      {:ok, candidates} when is_list(candidates) and length(candidates) > 0 ->
        candidates
      _ ->
        deterministic_candidates(content, weight)
    end
  end

  defp deterministic_candidates(content, weight) do
    cond do
      String.contains?(content, "?") ->
        [%{action: "answer", expected_reward: 0.8, confidence: weight, risk_level: 0.1,
           reasoning: "question detected", context: ["qa"]}]
      String.contains?(content, "fix") or String.contains?(content, "bug") ->
        [%{action: "diagnose", expected_reward: 0.7, confidence: weight * 0.8, risk_level: 0.3,
           reasoning: "bug fix request", context: ["debug"]}]
      String.contains?(content, "build") or String.contains?(content, "create") ->
        [%{action: "plan_and_build", expected_reward: 0.9, confidence: weight * 0.7, risk_level: 0.4,
           reasoning: "build request", context: ["implementation"]}]
      true ->
        [%{action: "respond", expected_reward: 0.6, confidence: weight * 0.9, risk_level: 0.05,
           reasoning: "general response", context: ["conversation"]}]
    end
  end

  defp call_llm_bridge(hemisphere, content) do
    url = Application.get_env(:odysseus_frontal_left, :llm_bridge_url, "http://localhost:3100")
    path = if hemisphere == :left, do: "/cortex/left", else: "/cortex/right"
    body = Jason.encode!(%{text: content})

    case :httpc.request(:post, {String.to_charlist(url <> path), [], 'application/json', body}, [timeout: 5000], []) do
      {:ok, {{_, 200, _}, _, resp_body}} ->
        case Jason.decode(to_string(resp_body)) do
          {:ok, %{"candidates" => candidates}} -> {:ok, candidates}
          _ -> {:error, :parse_error}
        end
      _ -> {:error, :bridge_unavailable}
    end
  rescue
    _ -> {:error, :bridge_error}
  end

  defp update_context(state, signal) do
    entry = %{content: signal.content, at: System.system_time(:millisecond)}
    %{state |
      context_buffer: Enum.take([entry | state.context_buffer], 20),
      decision_history: Enum.take(state.decision_history ++ [entry], 100)
    }
  end
end
