defmodule Gavel.RulesTest do
  use ExUnit.Case, async: true

  alias Gavel.Rules
  alias Gavel.Rules.Bid
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

  describe "Event conversion round trip" do
    test "round trip of :opened event through to_gleam |> from_gleam" do
      event = %Event{
        type: :opened,
        config: valid_config()
      }

      assert {:opened, {:config, _, _, _, _, _, _, _, _}} = Event.to_gleam(event)
      assert event |> Event.to_gleam() |> Event.from_gleam() == event
    end

    test "round trip of :bid_accepted event through to_gleam |> from_gleam" do
      event = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-1",
          bidder: "bob",
          amount: 1_500,
          at: 1_700_000_001_000
        }
      }

      assert {:bid_accepted, {:bid, "req-1", "bob", 1_500, 1_700_000_001_000}} =
               Event.to_gleam(event)

      assert event |> Event.to_gleam() |> Event.from_gleam() == event
    end

    test "round trip of :extended event through to_gleam |> from_gleam" do
      event = %Event{
        type: :extended,
        ends_at: 1_700_000_030_000
      }

      assert {:extended, 1_700_000_030_000} = Event.to_gleam(event)
      assert event |> Event.to_gleam() |> Event.from_gleam() == event
    end

    test "round trip of :closed event with winner through to_gleam |> from_gleam" do
      event = %Event{
        type: :closed,
        winner: %Bid{
          request_id: "req-1",
          bidder: "bob",
          amount: 1_500,
          at: 1_700_000_001_000
        }
      }

      assert {:auction_closed, {:some, {:bid, "req-1", "bob", 1_500, 1_700_000_001_000}}} =
               Event.to_gleam(event)

      assert event |> Event.to_gleam() |> Event.from_gleam() == event
    end

    test "round trip of :closed event with nil winner through to_gleam |> from_gleam" do
      event = %Event{
        type: :closed,
        winner: nil
      }

      assert {:auction_closed, :none} = Event.to_gleam(event)
      assert event |> Event.to_gleam() |> Event.from_gleam() == event
    end
  end

  describe "Bid conversion round trip" do
    test "round trip of %Bid{} through to_gleam |> from_gleam" do
      bid = %Bid{
        request_id: "req-42",
        bidder: "carol",
        amount: 2_500,
        at: 1_700_000_010_000
      }

      assert {:bid, "req-42", "carol", 2_500, 1_700_000_010_000} = Bid.to_gleam(bid)
      assert bid |> Bid.to_gleam() |> Bid.from_gleam() == bid
    end
  end
end
