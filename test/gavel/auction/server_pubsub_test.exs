defmodule Gavel.Auction.ServerPubsubTest do
  use Gavel.DataCase, async: false

  alias Gavel.Auction.Local
  alias Gavel.Clock
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
      title: "Signed Jersey",
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

  test "accepted bid broadcasts on auction topic", %{auction_id: auction_id} do
    Phoenix.PubSub.subscribe(Gavel.PubSub, "auction:" <> auction_id)

    {:accepted, _bid, _view} =
      Local.command(auction_id, {:place_bid, "req-pub-1", "bob", 1_000})

    assert_receive {:auction_event, ^auction_id, %Event{type: :bid_accepted}, %View{}}
  end

  test "accepted bid broadcasts on auctions summary topic", %{auction_id: auction_id} do
    Phoenix.PubSub.subscribe(Gavel.PubSub, "auctions")

    {:accepted, _bid, _view} =
      Local.command(auction_id, {:place_bid, "req-pub-2", "bob", 1_000})

    assert_receive {:auction_updated, ^auction_id, %View{}}
  end
end
