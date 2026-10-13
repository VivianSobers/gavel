defmodule Gavel.Cluster.PlacementTest do
  use Gavel.DataCase, async: false

  alias Gavel.Cluster.Placement
  alias Gavel.Rules.Config
  alias Gavel.Rules.Event
  alias Gavel.Store

  setup do
    on_exit(fn ->
      for {_, pid, _, _} <- DynamicSupervisor.which_children(Gavel.Auction.Supervisor) do
        DynamicSupervisor.terminate_child(Gavel.Auction.Supervisor, pid)
      end
    end)

    :ok
  end

  describe "reconcile/0 on one node" do
    test "starts open auctions owned by node and does not start closed auctions" do
      config1 = %Config{
        title: "Open Item 1",
        seller: "alice",
        starting_price: 1_000,
        reserve: 2_000,
        ends_at: 1_700_000_000_000,
        snipe_window_ms: 60_000,
        extension_ms: 30_000,
        max_extensions: 5
      }

      config2 = %Config{
        title: "Open Item 2",
        seller: "bob",
        starting_price: 500,
        reserve: 1_500,
        ends_at: 1_700_000_000_000,
        snipe_window_ms: 60_000,
        extension_ms: 30_000,
        max_extensions: 5
      }

      closed_config = %Config{
        title: "Closed Item",
        seller: "charlie",
        starting_price: 2_000,
        reserve: nil,
        ends_at: 1_600_000_000_000,
        snipe_window_ms: 60_000,
        extension_ms: 30_000,
        max_extensions: 5
      }

      {:ok, open_id1} = Store.create_auction(config1)
      {:ok, open_id2} = Store.create_auction(config2)
      {:ok, closed_id} = Store.create_auction(closed_config)

      close_event = %Event{
        type: :closed,
        winner: nil
      }

      assert {:ok, 2} = Store.append(closed_id, 1, [close_event])

      # None of the servers should be running before reconcile
      assert Registry.lookup(Gavel.Auction.Registry, open_id1) == []
      assert Registry.lookup(Gavel.Auction.Registry, open_id2) == []
      assert Registry.lookup(Gavel.Auction.Registry, closed_id) == []

      result = Placement.reconcile()

      assert %{started: started, stopped: []} = result
      assert Enum.sort(started) == Enum.sort([open_id1, open_id2])

      # Both open auctions are now started
      assert [{pid1, nil}] = Registry.lookup(Gavel.Auction.Registry, open_id1)
      assert Process.alive?(pid1)
      assert [{pid2, nil}] = Registry.lookup(Gavel.Auction.Registry, open_id2)
      assert Process.alive?(pid2)

      # Closed auction is not started
      assert Registry.lookup(Gavel.Auction.Registry, closed_id) == []
    end
  end
end
