defmodule Gavel.Auction.ServerDuplicateTest do
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

  test "same request twice returns original outcome and log has one bid", %{
    auction_id: auction_id
  } do
    assert {:accepted, %Bid{} = bid, %View{} = view} =
             Local.command(auction_id, {:place_bid, "req-1", "bob", 1_000})

    assert bid.request_id == "req-1"
    assert bid.bidder == "bob"
    assert bid.amount == 1_000
    assert view.seq == 2

    assert {:duplicate, %Bid{} = duplicate_bid, %View{} = duplicate_view} =
             Local.command(auction_id, {:place_bid, "req-1", "bob", 1_000})

    assert duplicate_bid == bid
    assert duplicate_view == view

    assert {:ok, events} = Store.load(auction_id)
    assert length(events) == 2
    assert Enum.map(events, & &1.type) == [:opened, :bid_accepted]
    assert Enum.count(events, &(&1.type == :bid_accepted)) == 1
  end

  test "duplicate after subsequent bid returns original bid and current view", %{
    auction_id: auction_id
  } do
    assert {:accepted, %Bid{} = first_bid, _view1} =
             Local.command(auction_id, {:place_bid, "req-1", "bob", 1_000})

    assert {:accepted, %Bid{} = _second_bid, %View{} = view2} =
             Local.command(auction_id, {:place_bid, "req-2", "carol", 1_100})

    assert view2.seq == 3
    assert view2.high_bid.bidder == "carol"

    assert {:duplicate, %Bid{} = dup_bid, %View{} = dup_view} =
             Local.command(auction_id, {:place_bid, "req-1", "bob", 1_000})

    assert dup_bid == first_bid
    assert dup_view.seq == 3
    assert dup_view.high_bid.bidder == "carol"

    assert {:ok, events} = Store.load(auction_id)
    assert length(events) == 3
    assert Enum.count(events, &(&1.type == :bid_accepted)) == 2
  end
end
