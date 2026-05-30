defmodule Odysseus.NeuronsTest do
  use ExUnit.Case
  doctest Odysseus.Neurons

  test "greets the world" do
    assert Odysseus.Neurons.hello() == :world
  end
end
