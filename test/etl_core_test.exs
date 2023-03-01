defmodule EtlCoreTest do
  use ExUnit.Case
  doctest EtlCore

  test "greets the world" do
    assert EtlCore.hello() == :world
  end
end
