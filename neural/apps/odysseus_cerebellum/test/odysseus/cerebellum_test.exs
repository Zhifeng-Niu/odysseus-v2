defmodule Odysseus.CerebellumTest do
  use ExUnit.Case
  doctest Odysseus.Cerebellum

  test "greets the world" do
    assert Odysseus.Cerebellum.hello() == :world
  end
end
