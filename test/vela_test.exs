defmodule VelaTest do
  use ExUnit.Case
  doctest Vela

  test "greets the world" do
    assert Vela.hello() == :world
  end
end
