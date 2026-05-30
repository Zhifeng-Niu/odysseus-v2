defmodule Odysseus.Basal.Nif do
  @moduledoc """
  Basal Ganglia NIF — holds Rust ganglia resource for action selection + habit formation.

  Rust NIF functions (loaded from libodysseus_basal.dylib):
    new_ganglia/0, select_action/2, record_execution/4,
    habit_count/1, has_habit/2
  """

  use GenServer

  @on_load :load_nifs

  defstruct [:ganglia]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ─── NIF Loading ─────────────────────────────────────────────

  def load_nifs do
    case :code.priv_dir(:odysseus_brain) do
      {:error, _} -> :ok
      priv ->
        path = Path.join([to_string(priv), "libodysseus_basal"])
        :erlang.load_nif(String.to_charlist(path), 0)
    end
  end

  def new_ganglia, do: :erlang.nif_error("basal NIF not loaded")
  def select_action(_res, _cands), do: :erlang.nif_error("basal NIF not loaded")
  def record_execution(_res, _action, _reward, _now), do: :erlang.nif_error("basal NIF not loaded")
  def habit_count(_res), do: :erlang.nif_error("basal NIF not loaded")
  def has_habit(_res, _action), do: :erlang.nif_error("basal NIF not loaded")

  # ─── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    Odysseus.WhiteMatter.subscribe(:basal)
    ganglia = safe_call(fn -> new_ganglia() end, nil)
    {:ok, %__MODULE__{ganglia: ganglia}}
  end

  @impl true
  def handle_info(%{type: :select_action, candidates: candidates}, state) do
    if state.ganglia and is_list(candidates) and length(candidates) > 0 do
      safe_call(fn ->
        case select_action(state.ganglia, candidates) do
          {:ok, selected} ->
            Odysseus.WhiteMatter.send_signal(:cerebellum, %{
              type: :motor_plan, action: selected.action,
              confidence: selected.confidence, reasoning: selected.reasoning
            })
          _ -> :ok
        end
      end, :ok)
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(%{type: :execution_result, action: action, reward: reward}, state) do
    if state.ganglia do
      now = System.system_time(:millisecond)
      safe_call(fn ->
        record_execution(state.ganglia, action, reward, now)
        if has_habit(state.ganglia, action) do
          Odysseus.WhiteMatter.send_signal(:frontal_left, %{type: :habit_formed, action: action})
        end
      end, :ok)
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(%{type: :error_signal, action: action, magnitude: magnitude}, state) do
    if state.ganglia do
      safe_call(fn ->
        record_execution(state.ganglia, action, -magnitude, System.system_time(:millisecond))
      end, :ok)
    end
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
