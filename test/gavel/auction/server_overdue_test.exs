defmodule Gavel.Auction.ServerOverdueTest do
  use Gavel.DataCase, async: false

  alias Gavel.Auction.Local
  alias Gavel.Auction.Server
  alias Gavel.Clock
  alias Gavel.Repo
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

    :ok
  end

  test "create with a past end time via the store, start the server, closed event stored" do
    now = 1_700_000_000_000
    past_end = now - 60_000
    Clock.Test.set(now)

    config = %Config{
      title: "Vintage Watch",
      seller: "alice",
      starting_price: 1_000,
      reserve: 2_000,
      ends_at: past_end,
      snipe_window_ms: 60_000,
      extension_ms: 30_000,
      max_extensions: 5
    }

    {:ok, auction_id} = Store.create_auction(config)

    Phoenix.PubSub.subscribe(Gavel.PubSub, "auction:" <> auction_id)
    Phoenix.PubSub.subscribe(Gavel.PubSub, "auctions")

    {:ok, pid} =
      DynamicSupervisor.start_child(Gavel.Auction.Supervisor, {Server, auction_id})

    # The server closes during handle_continue
    state = :sys.get_state(pid)
    assert state.view.status == :closed
    assert state.timer_ref == nil

    assert {:ok, events} = Store.load(auction_id)
    assert length(events) == 2
    assert List.last(events).type == :closed

    auction = Repo.get!(AuctionRecord, auction_id)
    assert auction.closed_at != nil

    assert_receive {:auction_event, ^auction_id, %Event{type: :closed}, %View{status: :closed}}
    assert_receive {:auction_updated, ^auction_id, %View{status: :closed}}
  end

  test "an Extended recorded before the crash is honoured (close happens only after the extended end)" do
    old_ends_at = 1_700_000_000_000
    Clock.Test.set(1_699_000_000_000)

    config = %Config{
      title: "Vintage Watch",
      seller: "alice",
      starting_price: 1_000,
      reserve: 2_000,
      ends_at: old_ends_at,
      snipe_window_ms: 60_000,
      extension_ms: 30_000,
      max_extensions: 5
    }

    {:ok, auction_id} = Store.create_auction(config)

    # Place a late bid within the snipe window (ends_at - 10s)
    late_bid_time = old_ends_at - 10_000
    Clock.Test.set(late_bid_time)

    assert {:accepted, %Bid{amount: 2_500} = bid, %View{} = view} =
             Local.command(auction_id, {:place_bid, "req-1", "bob", 2_500})

    extended_ends_at = late_bid_time + 30_000
    assert view.ends_at == extended_ends_at
    assert extended_ends_at > old_ends_at

    # Simulate crash: stop the running auction server
    [{pid, _}] = Registry.lookup(Gavel.Auction.Registry, auction_id)
    ref = Process.monitor(pid)
    :ok = DynamicSupervisor.terminate_child(Gavel.Auction.Supervisor, pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
    assert eventually(fn -> Registry.lookup(Gavel.Auction.Registry, auction_id) == [] end)

    # Time advances past original ends_at, but BEFORE extended_ends_at
    Clock.Test.set(old_ends_at + 5_000)

    # Start the server anew
    {:ok, new_pid} =
      DynamicSupervisor.start_child(Gavel.Auction.Supervisor, {Server, auction_id})

    state = :sys.get_state(new_pid)
    assert state.view.status == :open
    assert state.view.ends_at == extended_ends_at
    assert is_reference(state.timer_ref)

    assert {:ok, events} = Store.load(auction_id)
    refute Enum.any?(events, &(&1.type == :closed))

    auction = Repo.get!(AuctionRecord, auction_id)
    assert auction.closed_at == nil

    # Now time advances past the extended end: close happens only after the extended end
    Clock.Test.set(extended_ends_at + 1_000)
    send(new_pid, :close_due)

    state_after = :sys.get_state(new_pid)
    assert state_after.view.status == :closed
    assert state_after.timer_ref == nil

    assert {:ok, events_after} = Store.load(auction_id)
    assert List.last(events_after).type == :closed
    assert List.last(events_after).winner == bid

    auction_after = Repo.get!(AuctionRecord, auction_id)
    assert auction_after.closed_at != nil
  end

  test "server starting after extended ends_at closes during handle_continue" do
    old_ends_at = 1_700_000_000_000
    Clock.Test.set(1_699_000_000_000)

    config = %Config{
      title: "Vintage Watch",
      seller: "alice",
      starting_price: 1_000,
      reserve: 2_000,
      ends_at: old_ends_at,
      snipe_window_ms: 60_000,
      extension_ms: 30_000,
      max_extensions: 5
    }

    {:ok, auction_id} = Store.create_auction(config)

    late_bid_time = old_ends_at - 10_000
    Clock.Test.set(late_bid_time)

    assert {:accepted, %Bid{amount: 2_500} = bid, %View{}} =
             Local.command(auction_id, {:place_bid, "req-1", "bob", 2_500})

    extended_ends_at = late_bid_time + 30_000

    # Simulate crash
    [{pid, _}] = Registry.lookup(Gavel.Auction.Registry, auction_id)
    ref = Process.monitor(pid)
    :ok = DynamicSupervisor.terminate_child(Gavel.Auction.Supervisor, pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}
    assert eventually(fn -> Registry.lookup(Gavel.Auction.Registry, auction_id) == [] end)

    # Time advances AFTER extended ends_at
    Clock.Test.set(extended_ends_at + 10_000)

    # Start the server anew
    {:ok, new_pid} =
      DynamicSupervisor.start_child(Gavel.Auction.Supervisor, {Server, auction_id})

    state = :sys.get_state(new_pid)
    assert state.view.status == :closed
    assert state.timer_ref == nil

    assert {:ok, events} = Store.load(auction_id)
    assert List.last(events).type == :closed
    assert List.last(events).winner == bid

    auction = Repo.get!(AuctionRecord, auction_id)
    assert auction.closed_at != nil
  end

  test "server starting for already closed auction does not append closed event again" do
    now = 1_700_000_000_000
    Clock.Test.set(now)

    config = %Config{
      title: "Vintage Watch",
      seller: "alice",
      starting_price: 1_000,
      reserve: 2_000,
      ends_at: now + 60_000,
      snipe_window_ms: 60_000,
      extension_ms: 30_000,
      max_extensions: 5
    }

    {:ok, auction_id} = Store.create_auction(config)
    closed_event = %Event{type: :closed, winner: nil}
    {:ok, 2} = Store.append(auction_id, 1, [closed_event])

    {:ok, pid} =
      DynamicSupervisor.start_child(Gavel.Auction.Supervisor, {Server, auction_id})

    state = :sys.get_state(pid)
    assert state.view.status == :closed
    assert state.timer_ref == nil

    assert {:ok, events} = Store.load(auction_id)
    assert length(events) == 2
  end

  defp eventually(check, attempts \\ 50) do
    cond do
      check.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(10)
        eventually(check, attempts - 1)
    end
  end
end
