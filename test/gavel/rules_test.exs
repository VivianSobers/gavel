defmodule Gavel.RulesTest do
  use ExUnit.Case, async: true

  alias Gavel.Rules
  alias Gavel.Rules.Config
  alias Gavel.Rules.Event

  defp valid_config(attrs \\ %{}) do
    Map.merge(
      %Config{
        title: "Vintage Watch",
        seller: "alice",
        starting_price: 1_000,
        reserve: 5_000,
        ends_at: 1_700_000_000_000,
        snipe_window_ms: 60_000,
        extension_ms: 30_000,
        max_extensions: 5
      },
      Map.new(attrs)
    )
  end

  describe "open/1" do
    test "a valid config returns {:ok, [%Event{type: :opened}]}" do
      config = valid_config()

      assert {:ok, [%Event{type: :opened} = event]} = Rules.open(config)
      assert event.config == config
    end
  end

  describe "Config.to_gleam/1" do
    test "reserve: nil maps to :none" do
      config = valid_config(reserve: nil)

      assert {:config, "Vintage Watch", "alice", 1_000, :none, 1_700_000_000_000, 60_000, 30_000,
              5} = Config.to_gleam(config)
    end

    test "reserve with an integer amount maps to {:some, amount}" do
      config = valid_config(reserve: 5_000)

      assert {:config, "Vintage Watch", "alice", 1_000, {:some, 5_000}, 1_700_000_000_000, 60_000,
              30_000, 5} = Config.to_gleam(config)
    end

    test "a valid config with reserve: nil opens successfully" do
      config = valid_config(reserve: nil)

      assert {:ok, [%Event{type: :opened} = event]} = Rules.open(config)
      assert event.config.reserve == nil
    end
  end
end
