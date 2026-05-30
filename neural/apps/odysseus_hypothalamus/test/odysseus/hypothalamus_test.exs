defmodule Odysseus.HypothalamusTest do
  use ExUnit.Case
  doctest Odysseus.Hypothalamus

  test "greets the world" do
    assert Odysseus.Hypothalamus.hello() == :world
  end
end
