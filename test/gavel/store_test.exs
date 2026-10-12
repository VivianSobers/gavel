defmodule Gavel.StoreTest do
  use Gavel.DataCase, async: true

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
end
