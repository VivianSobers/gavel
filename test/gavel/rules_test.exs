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

  describe "from_gleam_rejection/1" do
    test "maps all nine rejections from Gleam to Elixir terms" do
      assert Rules.from_gleam_rejection({:invalid_config, "title"}) == {:invalid_config, "title"}
      assert Rules.from_gleam_rejection(:not_open) == :not_open
      assert Rules.from_gleam_rejection(:already_closed) == :already_closed
      assert Rules.from_gleam_rejection(:too_late) == :too_late
      assert Rules.from_gleam_rejection({:below_minimum, 1_000}) == {:below_minimum, 1_000}
      assert Rules.from_gleam_rejection(:invalid_amount) == :invalid_amount
      assert Rules.from_gleam_rejection(:seller_cannot_bid) == :seller_cannot_bid
      assert Rules.from_gleam_rejection(:already_high_bidder) == :already_high_bidder
      assert Rules.from_gleam_rejection(:not_yet_ended) == :not_yet_ended
    end
  end

  describe "open/1 invalid config rejections" do
    test "invalid title gives {:error, {:invalid_config, \"title\"}}" do
      assert Rules.open(valid_config(title: "")) == {:error, {:invalid_config, "title"}}
    end

    test "invalid seller gives {:error, {:invalid_config, \"seller\"}}" do
      assert Rules.open(valid_config(seller: "")) == {:error, {:invalid_config, "seller"}}
    end

    test "invalid starting_price gives {:error, {:invalid_config, \"starting_price\"}}" do
      assert Rules.open(valid_config(starting_price: 0)) ==
               {:error, {:invalid_config, "starting_price"}}

      assert Rules.open(valid_config(starting_price: -100)) ==
               {:error, {:invalid_config, "starting_price"}}
    end

    test "invalid reserve gives {:error, {:invalid_config, \"reserve\"}}" do
      assert Rules.open(valid_config(reserve: 0)) == {:error, {:invalid_config, "reserve"}}
      assert Rules.open(valid_config(reserve: -500)) == {:error, {:invalid_config, "reserve"}}
    end

    test "invalid ends_at gives {:error, {:invalid_config, \"ends_at\"}}" do
      assert Rules.open(valid_config(ends_at: 0)) == {:error, {:invalid_config, "ends_at"}}
      assert Rules.open(valid_config(ends_at: -1)) == {:error, {:invalid_config, "ends_at"}}
    end

    test "invalid snipe_window_ms gives {:error, {:invalid_config, \"snipe_window_ms\"}}" do
      assert Rules.open(valid_config(snipe_window_ms: -1)) ==
               {:error, {:invalid_config, "snipe_window_ms"}}
    end

    test "invalid extension_ms gives {:error, {:invalid_config, \"extension_ms\"}}" do
      assert Rules.open(valid_config(extension_ms: -1)) ==
               {:error, {:invalid_config, "extension_ms"}}
    end

    test "invalid max_extensions gives {:error, {:invalid_config, \"max_extensions\"}}" do
      assert Rules.open(valid_config(max_extensions: -1)) ==
               {:error, {:invalid_config, "max_extensions"}}
    end
  end
end
