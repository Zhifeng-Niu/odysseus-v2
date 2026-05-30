defmodule Odysseus.Neurons do
  @moduledoc """
  Neuron Layer — sparse associative memory with Hebbian learning.

  Delegates to Odysseus.Neurons.Nif for Rust NIF operations.
  """

  defstruct [:resource]

  @type t :: %__MODULE__{resource: reference()}

  def new do
    %__MODULE__{resource: Odysseus.Neurons.Nif.new_layer()}
  end

  def recall(%__MODULE__{resource: res}, cue) when is_list(cue) do
    {:ok, Odysseus.Neurons.Nif.recall(res, cue)}
  end

  def learn(%__MODULE__{resource: res}, experience, features, now)
      when is_list(features) and is_integer(now) do
    {:ok, Odysseus.Neurons.Nif.learn(res, experience, features, now)}
  end

  def reinforce(%__MODULE__{resource: res}, neuron_ids, levels, now)
      when is_list(neuron_ids) and is_list(levels) and is_integer(now) do
    :ok = Odysseus.Neurons.Nif.reinforce(res, neuron_ids, levels, now)
  end

  def tick_decay(%__MODULE__{resource: res}) do
    {:ok, Odysseus.Neurons.Nif.tick_decay(res)}
  end

  def save(%__MODULE__{resource: res}, path) when is_binary(path) do
    Odysseus.Neurons.Nif.save(res, path)
  end

  def load(%__MODULE__{resource: res}, path) when is_binary(path) do
    Odysseus.Neurons.Nif.load_layer(res, path)
  end

  def stats(%__MODULE__{resource: res}) do
    {:ok, Odysseus.Neurons.Nif.stats(res)}
  end
end
