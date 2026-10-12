defmodule Gavel.Auction.ServerTest do
  use Gavel.DataCase, async: false

  alias Gavel.Auction.Server
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

  test "starts and registers in Registry, folds events via handle_continue", %{
    auction_id: auction_id
  } do
    {:ok, pid} =
      DynamicSupervisor.start_child(Gavel.Auction.Supervisor, {Server, auction_id})

    assert [{^pid, nil}] = Registry.lookup(Gavel.Auction.Registry, auction_id)
  end

  test "unknown auction id stops with {:shutdown, :not_found}" do
    unknown_id = Ecto.UUID.generate()

    {:ok, pid} = DynamicSupervisor.start_child(Gavel.Auction.Supervisor, {Server, unknown_id})
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, {:shutdown, :not_found}}
  end
end
