defmodule Gavel.Cluster.PlacementTest do
  use Gavel.DataCase, async: false

  alias Gavel.Auction.Local
  alias Gavel.Cluster.Placement
  alias Gavel.Cluster.Ring
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

    test "stops local servers whose owner is another node" do
      config = %Config{
        title: "Test Item",
        seller: "alice",
        starting_price: 1_000,
        reserve: 2_000,
        ends_at: 1_700_000_000_000,
        snipe_window_ms: 60_000,
        extension_ms: 30_000,
        max_extensions: 5
      }

      {:ok, id1} = Store.create_auction(%{config | title: "Item 1"})
      {:ok, id2} = Store.create_auction(%{config | title: "Item 2"})

      assert {:ok, pid1} = Local.ensure_started(id1)
      assert {:ok, pid2} = Local.ensure_started(id2)
      _ = :sys.get_state(pid1)
      _ = :sys.get_state(pid2)

      other_node =
        Enum.find_value(Stream.iterate(1, &(&1 + 1)), fn i ->
          candidate = :"other_node_#{i}@host"
          r = Ring.new([node(), candidate])

          if Ring.owner(r, id1) == node() and Ring.owner(r, id2) == candidate do
            candidate
          end
        end)

      ring = Ring.new([node(), other_node])

      Application.put_env(:gavel, :ring_override, ring)
      on_exit(fn -> Application.delete_env(:gavel, :ring_override) end)

      result = Placement.reconcile()

      assert result.stopped == [id2]
      assert Registry.lookup(Gavel.Auction.Registry, id2) == []
      refute Process.alive?(pid2)

      assert [{^pid1, nil}] = Registry.lookup(Gavel.Auction.Registry, id1)
      assert Process.alive?(pid1)
    end
  end

  describe "cluster membership change and periodic placement" do
    test "reconciles and emits telemetry when membership change is broadcast" do
      test_pid = self()
      handler_id = "test-placement-reconcile-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:gavel, :placement, :reconcile],
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_reconcile, event_name, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      config = %Config{
        title: "Cluster Open Item",
        seller: "alice",
        starting_price: 1_000,
        reserve: 2_000,
        ends_at: 1_700_000_000_000,
        snipe_window_ms: 60_000,
        extension_ms: 30_000,
        max_extensions: 5
      }

      {:ok, open_id} = Store.create_auction(config)
      assert Registry.lookup(Gavel.Auction.Registry, open_id) == []

      Phoenix.PubSub.local_broadcast(Gavel.PubSub, "cluster", {:membership_changed, [node()]})

      assert_receive {:telemetry_reconcile, [:gavel, :placement, :reconcile], measurements,
                      metadata},
                     1_000

      assert is_integer(measurements.started)
      assert is_integer(measurements.stopped)
      assert measurements.started >= 1
      assert measurements.stopped == 0
      assert open_id in metadata.started

      assert [{pid, nil}] = Registry.lookup(Gavel.Auction.Registry, open_id)
      assert Process.alive?(pid)
    end

    test "reconciles on periodic interval" do
      test_pid = self()
      handler_id = "test-placement-interval-#{System.unique_integer()}"

      :telemetry.attach(
        handler_id,
        [:gavel, :placement, :reconcile],
        fn event_name, measurements, metadata, _config ->
          send(test_pid, {:telemetry_interval, event_name, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      {:ok, pid} =
        Placement.start_link(
          name: :"placement_interval_#{System.unique_integer()}",
          placement_interval_ms: 20
        )

      on_exit(fn ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
        end
      end)

      assert_receive {:telemetry_interval, [:gavel, :placement, :reconcile], measurements,
                      _metadata},
                     500

      assert is_integer(measurements.started)
      assert is_integer(measurements.stopped)
    end
  end
end
