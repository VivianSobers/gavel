defmodule Gavel.RulesTest do
  use ExUnit.Case, async: true

  alias Gavel.Rules
  alias Gavel.Rules.Bid
  alias Gavel.Rules.Config
  alias Gavel.Rules.Event
  alias Gavel.Rules.View

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

  describe "fold/1 and evolve/2" do
    test "fold/1 produces state from events" do
      config = valid_config()
      {:ok, [opened_event]} = Rules.open(config)

      state = Rules.fold([opened_event])
      assert state != nil
    end

    test "evolve/2 advances state stepwise matching fold/1" do
      config = valid_config()
      {:ok, [opened_event]} = Rules.open(config)
      state = Rules.fold([opened_event])

      bid_event = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-1",
          bidder: "bob",
          amount: 1_500,
          at: 1_700_000_001_000
        }
      }

      evolved_state = Rules.evolve(state, bid_event)
      folded_state = Rules.fold([opened_event, bid_event])
      assert evolved_state == folded_state
    end
  end

  describe "decide/3" do
    test "open, fold, decide a bid -> {:emit, [%Event{type: :bid_accepted}]}" do
      config = valid_config()
      {:ok, [opened_event]} = Rules.open(config)
      state = Rules.fold([opened_event])
      now = 1_699_999_000_000

      assert {:emit, [%Event{type: :bid_accepted} = bid_event]} =
               Rules.decide(state, {:place_bid, "req-1", "bob", 1_500}, now)

      assert bid_event.bid == %Bid{
               request_id: "req-1",
               bidder: "bob",
               amount: 1_500,
               at: now
             }
    end

    test "below minimum -> {:error, {:below_minimum, n}}" do
      config = valid_config(starting_price: 1_000)
      {:ok, [opened_event]} = Rules.open(config)
      state = Rules.fold([opened_event])
      now = 1_699_999_000_000

      assert Rules.decide(state, {:place_bid, "req-1", "bob", 500}, now) ==
               {:error, {:below_minimum, 1_000}}
    end

    test "repeat request -> {:duplicate, %Bid{}}" do
      config = valid_config()
      {:ok, [opened_event]} = Rules.open(config)
      state = Rules.fold([opened_event])
      now = 1_699_999_000_000

      assert {:emit, [bid_event]} =
               Rules.decide(state, {:place_bid, "req-1", "bob", 1_500}, now)

      state = Rules.evolve(state, bid_event)

      assert {:duplicate, %Bid{} = duplicate_bid} =
               Rules.decide(state, {:place_bid, "req-1", "bob", 2_000}, now + 1_000)

      assert duplicate_bid == %Bid{
               request_id: "req-1",
               bidder: "bob",
               amount: 1_500,
               at: now
             }
    end

    test "close before end -> {:error, :not_yet_ended}" do
      config = valid_config(ends_at: 1_700_000_000_000)
      {:ok, [opened_event]} = Rules.open(config)
      state = Rules.fold([opened_event])

      assert Rules.decide(state, :close, 1_699_999_000_000) == {:error, :not_yet_ended}
    end

    test "close after end -> {:emit, [%Event{type: :closed}]}" do
      config = valid_config(ends_at: 1_700_000_000_000, reserve: 1_000)
      {:ok, [opened_event]} = Rules.open(config)
      state = Rules.fold([opened_event])
      now = 1_699_999_000_000

      {:emit, [bid_event]} =
        Rules.decide(state, {:place_bid, "req-1", "bob", 1_500}, now)

      state = Rules.evolve(state, bid_event)

      assert {:emit, [%Event{type: :closed} = close_event]} =
               Rules.decide(state, :close, 1_700_000_000_001)

      assert close_event.winner == %Bid{
               request_id: "req-1",
               bidder: "bob",
               amount: 1_500,
               at: now
             }
    end
  end

  describe "view/1" do
    test "projects view from an opened auction state with no bids" do
      config = valid_config(starting_price: 1_000, reserve: 5_000)
      {:ok, [opened_event]} = Rules.open(config)
      state = Rules.fold([opened_event])

      assert %View{} = view = Rules.view(state)
      assert view.title == "Vintage Watch"
      assert view.seller == "alice"
      assert view.status == :open
      assert view.high_bid == nil
      assert view.recent_bids == []
      assert view.minimum_next_bid == 1_000
      assert view.ends_at == 1_700_000_000_000
      assert view.seq == 1
      assert view.reserve_met == false
    end

    test "reserve_met is true when there is no reserve" do
      config = valid_config(reserve: nil)
      {:ok, [opened_event]} = Rules.open(config)
      state = Rules.fold([opened_event])

      view = Rules.view(state)
      assert view.reserve_met == true

      now = 1_699_000_000_000
      {:emit, [bid_event]} = Rules.decide(state, {:place_bid, "req-1", "bob", 1_500}, now)
      state = Rules.evolve(state, bid_event)

      view_after_bid = Rules.view(state)
      assert view_after_bid.reserve_met == true
    end

    test "reserve_met evaluates correctly against high bid amount" do
      config = valid_config(reserve: 5_000, starting_price: 1_000)
      {:ok, [opened_event]} = Rules.open(config)
      state = Rules.fold([opened_event])

      now = 1_699_000_000_000

      # Below reserve (3_000 < 5_000)
      {:emit, [bid_1]} = Rules.decide(state, {:place_bid, "req-1", "bob", 3_000}, now)
      state = Rules.evolve(state, bid_1)
      assert Rules.view(state).reserve_met == false

      # Meets reserve exactly (5_000 == 5_000)
      {:emit, [bid_2]} = Rules.decide(state, {:place_bid, "req-2", "carol", 5_000}, now + 1_000)
      state = Rules.evolve(state, bid_2)
      assert Rules.view(state).reserve_met == true

      # Exceeds reserve (6_000 > 5_000)
      {:emit, [bid_3]} = Rules.decide(state, {:place_bid, "req-3", "bob", 6_000}, now + 2_000)
      state = Rules.evolve(state, bid_3)
      assert Rules.view(state).reserve_met == true
    end

    test "with 25 bids: recent_bids has 20, newest first" do
      config = valid_config(starting_price: 1_000, reserve: 2_000)
      {:ok, [opened_event]} = Rules.open(config)
      initial_state = Rules.fold([opened_event])

      base_time = 1_699_000_000_000

      state =
        Enum.reduce(1..25, initial_state, fn i, acc_state ->
          bidder = if rem(i, 2) == 1, do: "bidder_a", else: "bidder_b"
          amount = 1_000 + i * 100
          at = base_time + i * 1_000

          {:emit, [bid_event]} =
            Rules.decide(acc_state, {:place_bid, "req-#{i}", bidder, amount}, at)

          Rules.evolve(acc_state, bid_event)
        end)

      view = Rules.view(state)

      assert %View{} = view
      assert length(view.recent_bids) == 20
      assert Enum.map(view.recent_bids, & &1.request_id) == Enum.map(25..6//-1, &"req-#{&1}")
      assert hd(view.recent_bids).amount == 3_500
      assert hd(view.recent_bids).bidder == "bidder_a"
      assert List.last(view.recent_bids).amount == 1_600
      assert List.last(view.recent_bids).bidder == "bidder_b"

      assert view.high_bid == %Bid{
               request_id: "req-25",
               bidder: "bidder_a",
               amount: 3_500,
               at: base_time + 25 * 1_000
             }

      assert view.minimum_next_bid == 3_600
      assert view.seq == 26
      assert view.status == :open
      assert view.reserve_met == true
    end

    test "projects status :closed when auction is closed" do
      config = valid_config(ends_at: 1_700_000_000_000)
      {:ok, [opened_event]} = Rules.open(config)
      state = Rules.fold([opened_event])

      {:emit, [close_event]} = Rules.decide(state, :close, 1_700_000_000_001)
      closed_state = Rules.evolve(state, close_event)

      view = Rules.view(closed_state)
      assert view.status == :closed
      assert view.seq == 2
    end
  end

  describe "validate_history/1" do
    test "valid list -> {:ok, %View{}}" do
      config = valid_config(starting_price: 1_000, reserve: 2_000, ends_at: 1_700_000_000_000)
      {:ok, [opened_event]} = Rules.open(config)

      bid_event = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-1",
          bidder: "bob",
          amount: 1_500,
          at: 1_699_000_000_000
        }
      }

      assert {:ok, %View{} = view} = Rules.validate_history([opened_event, bid_event])
      assert view.title == "Vintage Watch"
      assert view.status == :open
      assert view.high_bid == bid_event.bid
      assert view.seq == 2
      assert view.minimum_next_bid == 1_600
      assert view.reserve_met == false
    end

    test "tampered amount -> {:error, {:rejected, 2, _}}" do
      config = valid_config(starting_price: 1_000)
      {:ok, [opened_event]} = Rules.open(config)

      tampered_bid = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-1",
          bidder: "bob",
          amount: 500,
          at: 1_699_000_000_000
        }
      }

      assert {:error, {:rejected, 2, rejection}} =
               Rules.validate_history([opened_event, tampered_bid])

      assert rejection == {:below_minimum, 1_000}
    end

    test "empty list or non-opened first event -> {:error, :missing_opened}" do
      assert Rules.validate_history([]) == {:error, :missing_opened}

      bid_event = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-1",
          bidder: "bob",
          amount: 1_500,
          at: 1_699_000_000_000
        }
      }

      assert Rules.validate_history([bid_event]) == {:error, :missing_opened}
    end

    test "unexpected sequence -> {:error, {:unexpected, seq}}" do
      config =
        valid_config(
          ends_at: 1_700_000_000_000,
          snipe_window_ms: 10_000,
          extension_ms: 10_000,
          max_extensions: 1
        )

      {:ok, [opened_event]} = Rules.open(config)

      bid_event = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-1",
          bidder: "bob",
          amount: 1_500,
          at: 1_699_999_995_000
        }
      }

      assert {:error, {:unexpected, 3}} = Rules.validate_history([opened_event, bid_event])
    end

    test "valid list through close -> {:ok, %View{status: :closed}}" do
      config = valid_config(starting_price: 1_000, reserve: 1_500, ends_at: 1_700_000_000_000)
      {:ok, [opened_event]} = Rules.open(config)

      bid_event = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-1",
          bidder: "bob",
          amount: 1_500,
          at: 1_699_000_000_000
        }
      }

      close_event = %Event{
        type: :closed,
        winner: bid_event.bid
      }

      assert {:ok, %View{} = view} =
               Rules.validate_history([opened_event, bid_event, close_event])

      assert view.status == :closed
      assert view.seq == 3
      assert view.reserve_met == true
      assert view.high_bid == bid_event.bid
    end
  end
end
