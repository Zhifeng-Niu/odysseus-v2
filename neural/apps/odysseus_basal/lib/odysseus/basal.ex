defmodule Odysseus.Basal do
  @moduledoc """
  Basal Ganglia — action selection and habit formation.

  Delegates to Odysseus.Basal.Nif for Rust NIF operations.
  """

  defstruct [:resource]

  @type t :: %__MODULE__{resource: reference()}

  def new do
    %__MODULE__{resource: Odysseus.Basal.Nif.new_ganglia()}
  end

  def select_action(%__MODULE__{resource: res}, candidates) when is_list(candidates) do
    {:ok, Odysseus.Basal.Nif.select_action(res, candidates)}
  end

  def record_execution(%__MODULE__{resource: res}, action, reward, now)
      when is_binary(action) and is_number(reward) and is_integer(now) do
    :ok = Odysseus.Basal.Nif.record_execution(res, action, reward, now)
  end

  def habit_count(%__MODULE__{resource: res}) do
    {:ok, Odysseus.Basal.Nif.habit_count(res)}
  end

  def has_habit?(%__MODULE__{resource: res}, action) when is_binary(action) do
    Odysseus.Basal.Nif.has_habit(res, action)
  end
end
