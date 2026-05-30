defmodule Odysseus.AmygdalaTest do
  use ExUnit.Case
  doctest Odysseus.Amygdala

  test "greets the world" do
    assert Odysseus.Amygdala.hello() == :world
  end
end
