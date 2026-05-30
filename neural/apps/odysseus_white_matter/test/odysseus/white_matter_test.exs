defmodule Odysseus.WhiteMatterTest do
  use ExUnit.Case
  doctest Odysseus.WhiteMatter

  test "greets the world" do
    assert Odysseus.WhiteMatter.hello() == :world
  end
end
