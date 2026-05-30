defmodule Odysseus.BasalTest do
  use ExUnit.Case
  doctest Odysseus.Basal

  test "greets the world" do
    assert Odysseus.Basal.hello() == :world
  end
end
