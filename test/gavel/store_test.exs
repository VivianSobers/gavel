defmodule Gavel.StoreTest do
  use Gavel.DataCase, async: true

  alias Gavel.Rules.Config
  alias Gavel.Rules.Event
  alias Gavel.Store
  alias Gavel.Store.AuctionRecord
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
end
