defmodule Gavel.Auction.ServerBidTest do
  use Gavel.DataCase, async: false

  alias Gavel.Auction.Local
  alias Gavel.Clock
  alias Gavel.Rules.Bid
  alias Gavel.Rules.Config
  alias Gavel.Rules.View
  alias Gavel.Store

  setup do
    on_exit(fn ->
      for {_, pid, _, _} <- DynamicSupervisor.which_children(Gavel.Auction.Supervisor) do
        DynamicSupervisor.terminate_child(Gavel.Auction.Supervisor, pid)
      end
    end)

    Clock.Test.set(1_699_000_000_000)

    config = %Config{
      title: "Vintage Watch",
      seller: "alice",
      starting_price: 1_000,
      reserve: nil,
      ends_at: 1_700_000_000_000,
      snipe_window_ms: 60_000,
      extension_ms: 30_000,
      max_extensions: 5
    }

    {:ok, auction_id} = Store.create_auction(config)
    %{auction_id: auction_id}
  end

  test "accepted bid is in Store.load", %{auction_id: auction_id} do
    assert {:accepted, %Bid{} = bid, %View{} = view} =
             Local.command(auction_id, {:place_bid, "req-1", "bob", 1_000})

    assert bid.request_id == "req-1"
    assert bid.bidder == "bob"
    assert bid.amount == 1_000
    assert view.seq == 2

    assert {:ok, events} = Store.load(auction_id)
    assert length(events) == 2
    bid_event = List.last(events)
    assert bid_event.type == :bid_accepted
    assert bid_event.bid.request_id == "req-1"
  end

  test "rejected bid is not in Store.load", %{auction_id: auction_id} do
    assert {:rejected, {:below_minimum, 1_000}} =
             Local.command(auction_id, {:place_bid, "req-bad", "bob", 500})

    assert {:ok, events} = Store.load(auction_id)
    assert length(events) == 1
    assert hd(events).type == :opened
  end
end
