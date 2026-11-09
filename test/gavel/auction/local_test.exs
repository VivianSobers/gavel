defmodule Gavel.Auction.LocalTest do
  use Gavel.DataCase, async: false

  alias Gavel.Auction.Local
  alias Gavel.Rules.Config
  alias Gavel.Store

  setup do
    on_exit(fn ->
      for {_, pid, _, _} <- DynamicSupervisor.which_children(Gavel.Auction.Supervisor) do
        DynamicSupervisor.terminate_child(Gavel.Auction.Supervisor, pid)
      end
    end)

    config = %Config{
      title: "Vintage Watch",
      seller: "alice",
      starting_price: 1_000,
      reserve: 5_000,
      ends_at: 1_700_000_000_000,
      snipe_window_ms: 60_000,
      extension_ms: 30_000,
      max_extensions: 5
    }

    {:ok, auction_id} = Store.create_auction(config)
    %{auction_id: auction_id, config: config}
  end

  test "first command starts one server", %{auction_id: auction_id} do
    assert Registry.lookup(Gavel.Auction.Registry, auction_id) == []

    assert {:view, %Gavel.Rules.View{}} = Local.command(auction_id, :view)

    assert [{pid, nil}] = Registry.lookup(Gavel.Auction.Registry, auction_id)
    assert Process.alive?(pid)
    assert length(DynamicSupervisor.which_children(Gavel.Auction.Supervisor)) == 1
  end

  test "second command reuses the existing server", %{auction_id: auction_id} do
    assert {:view, %Gavel.Rules.View{}} = Local.command(auction_id, :view)
    assert [{first_pid, _}] = Registry.lookup(Gavel.Auction.Registry, auction_id)

    assert {:view, %Gavel.Rules.View{}} = Local.command(auction_id, :view)
    assert [{second_pid, _}] = Registry.lookup(Gavel.Auction.Registry, auction_id)

    assert first_pid == second_pid
    assert length(DynamicSupervisor.which_children(Gavel.Auction.Supervisor)) == 1
  end

  test "unknown id returns {:error, :not_found}" do
    unknown_id = Ecto.UUID.generate()

    assert Local.command(unknown_id, :view) == {:error, :not_found}
    # The Registry removes the stopped server's entry asynchronously.
    assert eventually(fn -> Registry.lookup(Gavel.Auction.Registry, unknown_id) == [] end)
  end

  test "handles race when starting server concurrently", %{auction_id: auction_id} do
    task1 = Task.async(fn -> Local.command(auction_id, :view) end)
    task2 = Task.async(fn -> Local.command(auction_id, :view) end)

    assert {:view, %Gavel.Rules.View{}} = Task.await(task1)
    assert {:view, %Gavel.Rules.View{}} = Task.await(task2)

    assert [{pid, _}] = Registry.lookup(Gavel.Auction.Registry, auction_id)
    assert Process.alive?(pid)
    assert length(DynamicSupervisor.which_children(Gavel.Auction.Supervisor)) == 1
  end

  test "returns stale when placement stops the server during a call", %{auction_id: auction_id} do
    assert {:ok, pid} = Local.ensure_started(auction_id)
    :sys.suspend(pid)

    task = Task.async(fn -> Local.command(auction_id, :view) end)
    assert eventually(fn -> Process.info(pid, :message_queue_len) == {:message_queue_len, 1} end)

    assert :ok = DynamicSupervisor.terminate_child(Gavel.Auction.Supervisor, pid)

    assert {:error, :stale} = Task.await(task)
  end

  test "returns stale when the server crashes during a call", %{auction_id: auction_id} do
    assert {:ok, pid} = Local.ensure_started(auction_id)
    :sys.suspend(pid)

    task = Task.async(fn -> Local.command(auction_id, :view) end)
    assert eventually(fn -> Process.info(pid, :message_queue_len) == {:message_queue_len, 1} end)

    Process.exit(pid, :kill)

    assert {:error, :outcome_unknown} = Task.await(task)
  end

  describe "ensure_started/1" do
    test "starts server when not running and reuses existing server", %{auction_id: auction_id} do
      assert Registry.lookup(Gavel.Auction.Registry, auction_id) == []

      assert {:ok, pid1} = Local.ensure_started(auction_id)
      assert Process.alive?(pid1)
      assert [{^pid1, nil}] = Registry.lookup(Gavel.Auction.Registry, auction_id)

      assert {:ok, pid2} = Local.ensure_started(auction_id)
      assert pid1 == pid2
      assert length(DynamicSupervisor.which_children(Gavel.Auction.Supervisor)) == 1
    end
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
