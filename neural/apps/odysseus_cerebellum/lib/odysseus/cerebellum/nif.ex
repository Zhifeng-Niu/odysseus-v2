defmodule Odysseus.Cerebellum.Nif do
  @moduledoc """
  Cerebellum NIF — holds Rust predictor resource for forward prediction + error correction.

  Rust NIF functions (loaded from libodysseus_cerebellum.dylib):
    new_predictor/0, predict/2, observe_outcome/3,
    calibration/1, stats/1
  """

  use GenServer

  @on_load :load_nifs

  defstruct [:predictor]

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # ─── NIF Loading ─────────────────────────────────────────────

  def load_nifs do
    case :code.priv_dir(:odysseus_brain) do
      {:error, _} -> :ok
      priv ->
        path = Path.join([to_string(priv), "libodysseus_cerebellum"])
        :erlang.load_nif(String.to_charlist(path), 0)
    end
  end

  def new_predictor, do: :erlang.nif_error("cerebellum NIF not loaded")
  def predict(_res, _plan), do: :erlang.nif_error("cerebellum NIF not loaded")
  def observe_outcome(_res, _action, _actual), do: :erlang.nif_error("cerebellum NIF not loaded")
  def calibration(_res), do: :erlang.nif_error("cerebellum NIF not loaded")
  def stats(_res), do: :erlang.nif_error("cerebellum NIF not loaded")

  # ─── GenServer callbacks ─────────────────────────────────────

  @impl true
  def init(_opts) do
    Odysseus.WhiteMatter.subscribe(:cerebellum)
    predictor = try do
      new_predictor()
    rescue
      _ -> nil
    end
    {:ok, %__MODULE__{predictor: predictor}}
  end

  # Motor plan → predict outcome
  @impl true
  def handle_info(%{type: :motor_plan, action: action, confidence: confidence} = plan, state) do
    if state.predictor do
      try do
        predict(state.predictor, plan)
        cal = calibration(state.predictor)
        Odysseus.WhiteMatter.send_signal(:frontal_left, %{
          type: :prediction,
          action: action,
          expected_outcome: true,
          confidence: confidence * cal
        })
      rescue
        _ -> :ok
      end
    end
    {:noreply, state}
  end

  # Actual outcome → compare with prediction → error signal
  @impl true
  def handle_info(%{type: :actual_outcome, action: action, actual: actual}, state) do
    if state.predictor do
      try do
        result = observe_outcome(state.predictor, action, actual)
        case result do
          {magnitude, _direction} when magnitude > 0.1 ->
            error_signal = %{
              type: :error_signal, action: action,
              expected: "predicted", actual: actual,
              magnitude: magnitude, direction: :overestimate
            }
            Odysseus.WhiteMatter.send_signal(:basal, error_signal)
            Odysseus.WhiteMatter.send_signal(:frontal_left, error_signal)
          _ -> :ok
        end
      rescue
        _ -> :ok
      end
    end
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}
end
