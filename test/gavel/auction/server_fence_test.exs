defmodule Gavel.Auction.ServerFenceTest do
  use Gavel.DataCase, async: false

  alias Gavel.Auction.Local
  alias Gavel.Clock
  alias Gavel.Rules.Bid
  alias Gavel.Rules.Config
  alias Gavel.Rules.Event
  alias Gavel.Store

  setup do
    on_exit(fn ->
      for {_, pid, _, _} <- DynamicSupervisor.which_children(Gavel.Auction.Supervisor) do
        DynamicSupervisor.terminate_child(Gavel.Auction.Supervisor, pid)
      end
    end)

    Clock.Test.set(1_699_000_000_000)

    config = %Config{
      title: "Rare Coin",
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

  test "conflict returns stale, stops server, fresh restart sees extra event", %{
    auction_id: auction_id
  } do
    # Place a first bid so the server is running with seq = 2.
    assert {:accepted, _bid, view} =
             Local.command(auction_id, {:place_bid, "req-1", "bob", 1_000})

    assert view.seq == 2
    [{server_pid, _}] = Registry.lookup(Gavel.Auction.Registry, auction_id)
    ref = Process.monitor(server_pid)

    # Append an event directly behind the server's back (seq 3 in the DB).
    extra_event = %Event{
      type: :bid_accepted,
      bid: %Bid{request_id: "req-shadow", bidder: "carol", amount: 1_100, at: 1_699_000_000_001}
    }

    assert {:ok, 3} = Store.append(auction_id, 2, [extra_event])

    # The server still thinks seq = 2; its next append will collide with the seq-3 row.
    assert {:error, :stale} =
             Local.command(auction_id, {:place_bid, "req-2", "dan", 1_200})

    # The server process must be gone.
    assert_receive {:DOWN, ^ref, :process, ^server_pid, :normal}
    refute Process.alive?(server_pid)

    # The next command starts a fresh server that reloads all three events.
    assert {:accepted, _bid2, view2} =
             Local.command(auction_id, {:place_bid, "req-3", "dan", 1_200})

    assert view2.seq == 4
    assert view2.high_bid.bidder == "dan"
  end

  test "a stale server does not reject a bid that is already in the log", %{
    auction_id: auction_id
  } do
    assert {:accepted, _bid, %{seq: 2}} =
             Local.command(auction_id, {:place_bid, "req-1", "bob", 1_000})

    [{server_pid, _}] = Registry.lookup(Gavel.Auction.Registry, auction_id)
    ref = Process.monitor(server_pid)

    # Behind the server's back carol outbids bob and bob retakes the lead, so the
    # server still believes bob's first bid is high and that he cannot bid again.
    at = 1_699_000_000_001
    carol = %Bid{request_id: "req-2", bidder: "carol", amount: 5_000, at: at}
    bob = %Bid{request_id: "req-3", bidder: "bob", amount: 9_000, at: at}

    assert {:ok, 4} =
             Store.append(auction_id, 2, [
               %Event{type: :bid_accepted, bid: carol},
               %Event{type: :bid_accepted, bid: bob}
             ])

    assert {:error, :stale} =
             Local.command(auction_id, {:place_bid, "req-3", "bob", 9_000})

    assert_receive {:DOWN, ^ref, :process, ^server_pid, :normal}

    # A retry reaches a fresh server, which returns the original outcome.
    assert {:duplicate, ^bob, %{seq: 4}} =
             Local.command(auction_id, {:place_bid, "req-3", "bob", 9_000})
  end
end
