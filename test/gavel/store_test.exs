defmodule Gavel.StoreTest do
  use Gavel.DataCase, async: true

  alias Gavel.Clock
  alias Gavel.Rules.Bid
  alias Gavel.Rules.Config
  alias Gavel.Rules.Event
  alias Gavel.Store
  alias Gavel.Store.AuctionRecord
  alias Gavel.Store.Codec
  alias Gavel.Store.EventRecord

  test "inserting two events with the same (auction_id, seq) raises a unique violation" do
    now = DateTime.utc_now()

    auction =
      Repo.insert!(%AuctionRecord{
        title: "Vintage Watch",
        seller: "alice",
        config: %{"starting_price" => 100},
        ends_at: now
      })

    Repo.insert!(%EventRecord{
      auction_id: auction.id,
      seq: 1,
      type: "opened",
      payload: %{}
    })

    assert_raise Ecto.ConstraintError, ~r/events_pkey/, fn ->
      Repo.insert!(%EventRecord{
        auction_id: auction.id,
        seq: 1,
        type: "bid_accepted",
        payload: %{}
      })
    end
  end

  describe "create_auction/1" do
    test "creates an auction and inserts an opened event at seq 1" do
      config = %Config{
        title: "Vintage Watch",
        seller: "alice",
        starting_price: 1_000,
        reserve: 5_000,
        ends_at: 1_700_000_000_000,
        snipe_window_ms: 60_000,
        extension_ms: 30_000,
        max_extensions: 5
      }

      assert {:ok, auction_id} = Store.create_auction(config)
      assert is_binary(auction_id)

      auction = Repo.get!(AuctionRecord, auction_id)
      assert auction.title == "Vintage Watch"
      assert auction.seller == "alice"
      assert auction.ends_at == ~U[2023-11-14 22:13:20.000000Z]
      assert auction.closed_at == nil

      assert {:ok, [event]} = Store.load(auction_id)
      assert %Event{type: :opened, config: ^config} = event
    end

    test "invalid config inserts nothing and returns error" do
      config = %Config{
        title: "Vintage Watch",
        seller: "alice",
        starting_price: -100,
        reserve: 5_000,
        ends_at: 1_700_000_000_000,
        snipe_window_ms: 60_000,
        extension_ms: 30_000,
        max_extensions: 5
      }

      assert {:error, {:invalid_config, "starting_price"}} = Store.create_auction(config)
      assert Repo.all(AuctionRecord) == []
      assert Repo.all(EventRecord) == []
    end
  end

  describe "load/1" do
    test "returns {:error, :not_found} for unknown auction id" do
      unknown_id = Ecto.UUID.generate()
      assert Store.load(unknown_id) == {:error, :not_found}
    end

    test "returns events ordered by seq when inserted out of order" do
      now = DateTime.utc_now()

      auction =
        Repo.insert!(%AuctionRecord{
          title: "Vintage Watch",
          seller: "alice",
          config: %{"starting_price" => 100},
          ends_at: now
        })

      event1 = %Event{
        type: :opened,
        config: %Config{
          title: "Vintage Watch",
          seller: "alice",
          starting_price: 100,
          reserve: nil,
          ends_at: 1_000,
          snipe_window_ms: 10,
          extension_ms: 5,
          max_extensions: 2
        }
      }

      event2 = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-1",
          bidder: "bob",
          amount: 200,
          at: 500
        }
      }

      event3 = %Event{
        type: :closed,
        winner: %Bid{
          request_id: "req-1",
          bidder: "bob",
          amount: 200,
          at: 500
        }
      }

      {type1, payload1, req1} = Codec.encode(event1)
      {type2, payload2, req2} = Codec.encode(event2)
      {type3, payload3, req3} = Codec.encode(event3)

      # Insert out of order: seq 3, seq 1, seq 2
      Repo.insert!(%EventRecord{
        auction_id: auction.id,
        seq: 3,
        type: type3,
        payload: payload3,
        request_id: req3
      })

      Repo.insert!(%EventRecord{
        auction_id: auction.id,
        seq: 1,
        type: type1,
        payload: payload1,
        request_id: req1
      })

      Repo.insert!(%EventRecord{
        auction_id: auction.id,
        seq: 2,
        type: type2,
        payload: payload2,
        request_id: req2
      })

      assert {:ok, [loaded1, loaded2, loaded3]} = Store.load(auction.id)
      assert loaded1 == event1
      assert loaded2 == event2
      assert loaded3 == event3
    end
  end

  describe "append/3" do
    setup do
      config = %Config{
        title: "Vintage Watch",
        seller: "alice",
        starting_price: 100,
        reserve: nil,
        ends_at: 1_000,
        snipe_window_ms: 10,
        extension_ms: 5,
        max_extensions: 2
      }

      {:ok, auction_id} = Store.create_auction(config)
      %{auction_id: auction_id}
    end

    test "append at 1 returns {:ok, 2} and persists event", %{auction_id: auction_id} do
      event = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-1",
          bidder: "bob",
          amount: 200,
          at: 500
        }
      }

      assert {:ok, 2} = Store.append(auction_id, 1, [event])
      assert {:ok, [_opened, loaded_event]} = Store.load(auction_id)
      assert loaded_event == event
    end

    test "second append at 1 returns {:error, :conflict}", %{auction_id: auction_id} do
      event1 = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-1",
          bidder: "bob",
          amount: 200,
          at: 500
        }
      }

      event2 = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-2",
          bidder: "charlie",
          amount: 300,
          at: 600
        }
      }

      assert {:ok, 2} = Store.append(auction_id, 1, [event1])
      assert Store.append(auction_id, 1, [event2]) == {:error, :conflict}

      assert {:ok, [_opened, stored_event]} = Store.load(auction_id)
      assert stored_event == event1
    end

    test "two-event batch whose second seq collides stores neither", %{auction_id: auction_id} do
      colliding_event = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-preexisting",
          bidder: "dan",
          amount: 400,
          at: 700
        }
      }

      {type3, payload3, req3} = Codec.encode(colliding_event)

      Repo.insert!(%EventRecord{
        auction_id: auction_id,
        seq: 3,
        type: type3,
        payload: payload3,
        request_id: req3
      })

      batch_event1 = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-batch-1",
          bidder: "bob",
          amount: 200,
          at: 500
        }
      }

      batch_event2 = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-batch-2",
          bidder: "charlie",
          amount: 300,
          at: 600
        }
      }

      assert Store.append(auction_id, 1, [batch_event1, batch_event2]) == {:error, :conflict}

      assert Repo.get_by(EventRecord, auction_id: auction_id, seq: 2) == nil
      assert {:ok, [loaded1, loaded3]} = Store.load(auction_id)
      assert loaded1.type == :opened
      assert loaded3 == colliding_event
    end

    test "two different seqs with the same request id returns {:error, :conflict}", %{
      auction_id: auction_id
    } do
      event1 = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-duplicate",
          bidder: "bob",
          amount: 200,
          at: 500
        }
      }

      event2 = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-duplicate",
          bidder: "charlie",
          amount: 300,
          at: 600
        }
      }

      assert {:ok, 2} = Store.append(auction_id, 1, [event1])
      assert Store.append(auction_id, 2, [event2]) == {:error, :conflict}

      assert {:ok, [_opened, stored_event]} = Store.load(auction_id)
      assert stored_event == event1
    end

    test "appending a :closed event sets auctions.closed_at", %{auction_id: auction_id} do
      Clock.Test.set(1_700_000_100_000)

      event = %Event{
        type: :closed,
        winner: %Bid{
          request_id: "req-1",
          bidder: "bob",
          amount: 200,
          at: 500
        }
      }

      assert {:ok, 2} = Store.append(auction_id, 1, [event])

      auction = Repo.get!(AuctionRecord, auction_id)
      assert auction.closed_at == ~U[2023-11-14 22:15:00.000000Z]
    end

    test "a conflicting close leaves auctions.closed_at null", %{auction_id: auction_id} do
      prior_event = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-1",
          bidder: "bob",
          amount: 200,
          at: 500
        }
      }

      assert {:ok, 2} = Store.append(auction_id, 1, [prior_event])

      close_event = %Event{
        type: :closed,
        winner: nil
      }

      assert Store.append(auction_id, 1, [close_event]) == {:error, :conflict}

      auction = Repo.get!(AuctionRecord, auction_id)
      assert auction.closed_at == nil
    end
  end

  describe "open_auction_ids/0" do
    test "returns ids of auctions where closed_at is nil" do
      open_config = %Config{
        title: "Open Auction",
        seller: "alice",
        starting_price: 100,
        reserve: nil,
        ends_at: 1_000,
        snipe_window_ms: 10,
        extension_ms: 5,
        max_extensions: 2
      }

      closed_config = %Config{
        title: "Closed Auction",
        seller: "bob",
        starting_price: 200,
        reserve: nil,
        ends_at: 2_000,
        snipe_window_ms: 10,
        extension_ms: 5,
        max_extensions: 2
      }

      {:ok, open_id} = Store.create_auction(open_config)
      {:ok, closed_id} = Store.create_auction(closed_config)

      close_event = %Event{
        type: :closed,
        winner: nil
      }

      assert {:ok, 2} = Store.append(closed_id, 1, [close_event])

      assert Store.open_auction_ids() == [open_id]
    end
  end
end
