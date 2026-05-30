defmodule Odysseus.Cerebellum do
  @moduledoc """
  Cerebellum — forward prediction and error correction.

  Delegates to Odysseus.Cerebellum.Nif for Rust NIF operations.
  """

  defstruct [:resource]

  @type t :: %__MODULE__{resource: reference()}

  def new do
    %__MODULE__{resource: Odysseus.Cerebellum.Nif.new_predictor()}
  end

  def predict(%__MODULE__{resource: res}, plan) do
    Odysseus.Cerebellum.Nif.predict(res, plan)
  end

  def observe_outcome(%__MODULE__{resource: res}, action, actual)
      when is_binary(action) and is_binary(actual) do
    {:ok, Odysseus.Cerebellum.Nif.observe_outcome(res, action, actual)}
  end

  def calibration(%__MODULE__{resource: res}) do
    {:ok, Odysseus.Cerebellum.Nif.calibration(res)}
  end

  def stats(%__MODULE__{resource: res}) do
    {:ok, Odysseus.Cerebellum.Nif.stats(res)}
  end
end
