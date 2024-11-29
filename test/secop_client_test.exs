defmodule SecopClientTest do
  use ExUnit.Case
  doctest SecopClient

  test "greets the world" do
    assert SecopClient.hello() == :world
  end
end
