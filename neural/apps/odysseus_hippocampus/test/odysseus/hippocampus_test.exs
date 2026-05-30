defmodule Odysseus.HippocampusTest do
  use ExUnit.Case
  doctest Odysseus.Hippocampus

  test "greets the world" do
    assert Odysseus.Hippocampus.hello() == :world
  end
end
