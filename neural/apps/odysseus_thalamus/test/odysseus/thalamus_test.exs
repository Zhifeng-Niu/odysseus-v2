defmodule Odysseus.ThalamusTest do
  use ExUnit.Case
  doctest Odysseus.Thalamus

  test "greets the world" do
    assert Odysseus.Thalamus.hello() == :world
  end
end
