defmodule Odysseus.Hippocampus do
  @moduledoc """
  Hippocampus — memory encoding with pattern separation/completion and activation spreading.

  Delegates to Odysseus.Hippocampus.Nif for Rust NIF operations.
  Encoding → consolidation → recall via activation spreading.
  """

  defstruct [:resource]

  @type t :: %__MODULE__{resource: reference()}

  def new do
    %__MODULE__{resource: Odysseus.Hippocampus.Nif.new_store()}
  end

  def store(%__MODULE__{resource: res}, experience, now) when is_integer(now) do
    {:ok, Odysseus.Hippocampus.Nif.store(res, experience, now)}
  end

  def recall(%__MODULE__{resource: res}, cue, now) when is_binary(cue) and is_integer(now) do
    Odysseus.Hippocampus.Nif.recall(res, cue, now)
  end

  def consolidate(%__MODULE__{resource: res}, now) when is_integer(now) do
    {:ok, Odysseus.Hippocampus.Nif.consolidate(res, now)}
  end

  def tick_decay(%__MODULE__{resource: res}) do
    {:ok, Odysseus.Hippocampus.Nif.tick_decay(res)}
  end

  def stats(%__MODULE__{resource: res}) do
    {:ok, Odysseus.Hippocampus.Nif.stats(res)}
  end
end
