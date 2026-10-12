defmodule Gavel.Auction.ServerExtensionTest do
  use Gavel.DataCase, async: false

  alias Gavel.Auction.Local
  alias Gavel.Clock
  alias Gavel.Rules.Bid
  alias Gavel.Rules.Config
  alias Gavel.Rules.Event
  alias Gavel.Rules.View
  alias Gavel.Store
  alias Gavel.Store.AuctionRecord

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
      reserve: 2_000,
      ends_at: 1_700_000_000_000,
      snipe_window_ms: 60_000,
      extension_ms: 30_000,
      max_extensions: 5
    }

    {:ok, auction_id} = Store.create_auction(config)
    %{auction_id: auction_id, ends_at: config.ends_at}
  end

  test "an :extended event moves the timer", %{
    auction_id: auction_id,
    ends_at: old_ends_at
  } do
    assert {:view, %View{}} = Local.command(auction_id, :view)
    [{pid, _}] = Registry.lookup(Gavel.Auction.Registry, auction_id)
    initial_timer_ref = :sys.get_state(pid).timer_ref
    assert is_reference(initial_timer_ref)

    late_bid_time = old_ends_at - 10_000
    Clock.Test.set(late_bid_time)

    assert {:accepted, _bid, view} =
             Local.command(auction_id, {:place_bid, "req-1", "bob", 2_500})

    assert view.ends_at == late_bid_time + 30_000

    new_timer_ref = :sys.get_state(pid).timer_ref
    assert is_reference(new_timer_ref)
    assert new_timer_ref != initial_timer_ref
  end

  test "late bid extends; :close_due at the old end time does not close; at the new end time it does",
       %{auction_id: auction_id, ends_at: old_ends_at} do
    Phoenix.PubSub.subscribe(Gavel.PubSub, "auction:" <> auction_id)
    Phoenix.PubSub.subscribe(Gavel.PubSub, "auctions")

    # Place a late bid within snipe window (ends_at - 10s)
    late_bid_time = old_ends_at - 10_000
    Clock.Test.set(late_bid_time)

    assert {:accepted, %Bid{amount: 2_500} = bid, %View{} = view} =
             Local.command(auction_id, {:place_bid, "req-1", "bob", 2_500})

    # The extension adds 30s from the bid time, extending to old_ends_at + 20s
    expected_new_ends_at = late_bid_time + 30_000
    assert expected_new_ends_at > old_ends_at
    assert view.ends_at == expected_new_ends_at

    # PubSub broadcast has both :bid_accepted and :extended
    assert_receive {:auction_event, ^auction_id, %Event{type: :bid_accepted}, _view}

    assert_receive {:auction_event, ^auction_id,
                    %Event{type: :extended, ends_at: ^expected_new_ends_at}, _view}

    [{pid, _}] = Registry.lookup(Gavel.Auction.Registry, auction_id)

    # 1. At the old end time, :close_due does not close the auction
    Clock.Test.set(old_ends_at)
    send(pid, :close_due)
    _ = :sys.get_state(pid)

    assert {:ok, events} = Store.load(auction_id)
    refute Enum.any?(events, &(&1.type == :closed))

    auction = Repo.get!(AuctionRecord, auction_id)
    assert auction.closed_at == nil

    assert {:view, %View{status: :open}} = Local.command(auction_id, :view)

    # 2. At the new end time, :close_due closes the auction
    Clock.Test.set(expected_new_ends_at)
    send(pid, :close_due)

    assert_receive {:auction_event, ^auction_id, %Event{type: :closed, winner: ^bid},
                    %View{status: :closed}}

    assert_receive {:auction_updated, ^auction_id, %View{status: :closed}}

    assert {:ok, events_after} = Store.load(auction_id)
    assert List.last(events_after).type == :closed
    assert List.last(events_after).winner == bid

    auction_after = Repo.get!(AuctionRecord, auction_id)
    assert auction_after.closed_at != nil

    assert {:view, %View{status: :closed}} = Local.command(auction_id, :view)
  end

  test "multiple extensions reschedule the timer repeatedly until max_extensions", %{
    auction_id: auction_id,
    ends_at: old_ends_at
  } do
    t1 = old_ends_at - 10_000
    Clock.Test.set(t1)

    assert {:accepted, _bid1, view1} =
             Local.command(auction_id, {:place_bid, "req-1", "bob", 1_000})

    ends_at_1 = t1 + 30_000
    assert view1.ends_at == ends_at_1

    t2 = ends_at_1 - 5_000
    Clock.Test.set(t2)

    assert {:accepted, _bid2, view2} =
             Local.command(auction_id, {:place_bid, "req-2", "carol", 1_100})

    ends_at_2 = t2 + 30_000
    assert view2.ends_at == ends_at_2

    [{pid, _}] = Registry.lookup(Gavel.Auction.Registry, auction_id)

    Clock.Test.set(ends_at_1)
    send(pid, :close_due)
    _ = :sys.get_state(pid)

    assert {:ok, events} = Store.load(auction_id)
    refute Enum.any?(events, &(&1.type == :closed))

    Clock.Test.set(ends_at_2)
    send(pid, :close_due)
    _ = :sys.get_state(pid)

    assert {:ok, events_final} = Store.load(auction_id)
    assert List.last(events_final).type == :closed
  end
end
