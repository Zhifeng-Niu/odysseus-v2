defmodule Odysseus.Amygdala do
  @moduledoc """
  Amygdala — fast emotional evaluation (< 50ms target).

  Delegates to Odysseus.Amygdala.Nif for Rust NIF operations.
  """

  defstruct [:resource]

  @type t :: %__MODULE__{resource: reference()}

  def new do
    %__MODULE__{resource: Odysseus.Amygdala.Nif.new_state()}
  end

  def evaluate(%__MODULE__{resource: res}, text) when is_binary(text) do
    {:ok, Odysseus.Amygdala.Nif.evaluate(res, text)}
  end

  def state_summary(%__MODULE__{resource: res}) do
    {:ok, Odysseus.Amygdala.Nif.state_summary(res)}
  end
end
