defmodule Gavel.RulesInteropTest do
  use ExUnit.Case, async: true

  test "gleam rules module is callable from elixir" do
    assert :gavel_rules.version() == "0.1.0"
  end
end
