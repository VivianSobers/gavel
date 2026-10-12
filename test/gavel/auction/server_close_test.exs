defmodule Gavel.Auction.ServerCloseTest do
  use Gavel.DataCase, async: false

  alias Gavel.Auction.Local
  alias Gavel.Auction.Server
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

  test "advance past end and send :close_due closes auction, stores closed event and sets closed_at",
       %{auction_id: auction_id, ends_at: ends_at} do
    Phoenix.PubSub.subscribe(Gavel.PubSub, "auction:" <> auction_id)
    Phoenix.PubSub.subscribe(Gavel.PubSub, "auctions")

    assert {:accepted, %Bid{} = bid, _view} =
             Local.command(auction_id, {:place_bid, "req-1", "bob", 2_500})

    [{pid, _}] = Registry.lookup(Gavel.Auction.Registry, auction_id)

    Clock.Test.set(ends_at + 1_000)

    send(pid, :close_due)

    assert_receive {:auction_event, ^auction_id, %Event{type: :closed, winner: ^bid},
                    %View{status: :closed}}

    assert_receive {:auction_updated, ^auction_id, %View{status: :closed}}

    assert {:ok, events} = Store.load(auction_id)
    assert length(events) == 3
    assert List.last(events).type == :closed
    assert List.last(events).winner == bid

    auction = Repo.get!(AuctionRecord, auction_id)
    assert auction.closed_at != nil
  end

  test ":close_due before ends_at reschedules timer without closing",
       %{auction_id: auction_id} do
    {:accepted, _bid, _view} =
      Local.command(auction_id, {:place_bid, "req-1", "bob", 1_000})

    [{pid, _}] = Registry.lookup(Gavel.Auction.Registry, auction_id)

    Clock.Test.set(1_699_500_000_000)

    send(pid, :close_due)

    _ = :sys.get_state(pid)

    assert {:ok, events} = Store.load(auction_id)
    refute Enum.any?(events, &(&1.type == :closed))

    auction = Repo.get!(AuctionRecord, auction_id)
    assert auction.closed_at == nil
  end

  test "Local.command(id, :close) closes auction and replies {:closed, winner, view}",
       %{auction_id: auction_id, ends_at: ends_at} do
    assert {:accepted, %Bid{} = bid, _view} =
             Local.command(auction_id, {:place_bid, "req-1", "bob", 2_500})

    Clock.Test.set(ends_at + 1_000)

    assert {:closed, ^bid, %View{status: :closed} = view} =
             Local.command(auction_id, :close)

    assert view.status == :closed
    assert view.seq == 3

    assert {:ok, events} = Store.load(auction_id)
    assert List.last(events).type == :closed
    assert List.last(events).winner == bid

    auction = Repo.get!(AuctionRecord, auction_id)
    assert auction.closed_at != nil
  end

  test "Local.command(id, :close) returns {:rejected, :not_yet_ended} before end",
       %{auction_id: auction_id} do
    Clock.Test.set(1_699_500_000_000)

    assert {:rejected, :not_yet_ended} = Local.command(auction_id, :close)

    assert {:ok, events} = Store.load(auction_id)
    refute Enum.any?(events, &(&1.type == :closed))
  end

  test "Local.command(id, :close) returns {:rejected, :already_closed} when already closed",
       %{auction_id: auction_id, ends_at: ends_at} do
    Clock.Test.set(ends_at + 1_000)

    assert {:closed, nil, %View{status: :closed}} = Local.command(auction_id, :close)
    assert {:rejected, :already_closed} = Local.command(auction_id, :close)
  end

  test "closed auction without reserve met has winner as nil",
       %{auction_id: auction_id, ends_at: ends_at} do
    assert {:accepted, %Bid{}, _view} =
             Local.command(auction_id, {:place_bid, "req-1", "bob", 1_000})

    Clock.Test.set(ends_at + 1_000)

    assert {:closed, nil, %View{status: :closed}} =
             Local.command(auction_id, :close)

    assert {:ok, events} = Store.load(auction_id)
    assert List.last(events).winner == nil
  end

  test "timer is scheduled on init and cancelled/rescheduled on new events",
       %{auction_id: auction_id} do
    {:ok, pid} = DynamicSupervisor.start_child(Gavel.Auction.Supervisor, {Server, auction_id})
    state1 = :sys.get_state(pid)
    assert is_reference(state1.timer_ref)

    {:accepted, _bid, _view} = Local.command(auction_id, {:place_bid, "req-1", "bob", 1_000})
    state2 = :sys.get_state(pid)
    assert is_reference(state2.timer_ref)
    assert state2.timer_ref != state1.timer_ref
  end
end
