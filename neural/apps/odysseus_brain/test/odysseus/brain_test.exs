defmodule Odysseus.BrainTest do
  use ExUnit.Case
  doctest Odysseus.Brain

  test "greets the world" do
    assert Odysseus.Brain.hello() == :world
  end
end
