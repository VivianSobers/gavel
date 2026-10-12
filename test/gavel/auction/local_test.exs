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
