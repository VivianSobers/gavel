defmodule Gavel.Auction.ServerLingerTest do
  use Gavel.DataCase, async: false

  alias Gavel.Auction.Local
  alias Gavel.Auction.Server
  alias Gavel.Clock
  alias Gavel.Rules.Bid
  alias Gavel.Rules.Config
  alias Gavel.Rules.Event
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
      reserve: 2_000,
      ends_at: 1_700_000_000_000,
      snipe_window_ms: 60_000,
      extension_ms: 30_000,
      max_extensions: 5
    }

    {:ok, auction_id} = Store.create_auction(config)
    %{auction_id: auction_id, ends_at: config.ends_at}
  end

  test "server stops normally after linger when closed by timer", %{
    auction_id: auction_id,
    ends_at: ends_at
  } do
    assert {:accepted, %Bid{}, _view} =
             Local.command(auction_id, {:place_bid, "req-1", "bob", 2_500})

    [{pid, _}] = Registry.lookup(Gavel.Auction.Registry, auction_id)
    ref = Process.monitor(pid)

    Clock.Test.set(ends_at + 1_000)
    send(pid, :close_due)

    # During linger: process is alive and commands get {:rejected, :already_closed}
    assert Process.alive?(pid)

    assert {:rejected, :already_closed} =
             Local.command(auction_id, {:place_bid, "req-late", "charlie", 3_000})

    assert {:rejected, :already_closed} = Local.command(auction_id, :close)

    # After linger: process exits normally and is removed from registry
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    refute Process.alive?(pid)
    assert eventually(fn -> Registry.lookup(Gavel.Auction.Registry, auction_id) == [] end)
  end

  test "server stops normally after linger when closed by command", %{
    auction_id: auction_id,
    ends_at: ends_at
  } do
    assert {:view, %View{status: :open}} = Local.command(auction_id, :view)
    [{pid, _}] = Registry.lookup(Gavel.Auction.Registry, auction_id)
    ref = Process.monitor(pid)

    Clock.Test.set(ends_at + 1_000)
    assert {:closed, nil, %View{status: :closed}} = Local.command(auction_id, :close)

    # During linger: process is alive and commands get {:rejected, :already_closed}
    assert Process.alive?(pid)

    assert {:rejected, :already_closed} =
             Local.command(auction_id, {:place_bid, "req-after-close", "bob", 1_500})

    assert {:rejected, :already_closed} = Local.command(auction_id, :close)

    # After linger: process exits normally and is removed from registry
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    refute Process.alive?(pid)
    assert eventually(fn -> Registry.lookup(Gavel.Auction.Registry, auction_id) == [] end)
  end

  test "server started for an already closed auction stops normally after linger", %{
    auction_id: auction_id
  } do
    closed_event = %Event{type: :closed, winner: nil}
    {:ok, 2} = Store.append(auction_id, 1, [closed_event])

    {:ok, pid} = DynamicSupervisor.start_child(Gavel.Auction.Supervisor, {Server, auction_id})
    ref = Process.monitor(pid)

    # During linger: process is alive and commands get {:rejected, :already_closed}
    assert Process.alive?(pid)

    assert {:rejected, :already_closed} =
             Local.command(auction_id, {:place_bid, "req-closed-start", "bob", 1_000})

    assert {:rejected, :already_closed} = Local.command(auction_id, :close)

    # After linger: process exits normally and is removed from registry
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 500
    refute Process.alive?(pid)
    assert eventually(fn -> Registry.lookup(Gavel.Auction.Registry, auction_id) == [] end)
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
