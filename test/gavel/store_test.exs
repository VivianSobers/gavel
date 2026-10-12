defmodule Gavel.StoreTest do
  use Gavel.DataCase, async: true

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
end
