defmodule Gavel.Cluster.FailoverTest do
  use Gavel.ClusterCase

  import Ecto.Query

  alias Gavel.Auction.Registry, as: AuctionRegistry
  alias Gavel.Clock
  alias Gavel.Repo
  alias Gavel.Router
  alias Gavel.Rules.Bid
  alias Gavel.Rules.Config
  alias Gavel.Store
  alias Gavel.Store.EventRecord

  @auctions 12

  # The clock peers run on; Gavel.Clock on this node is the test double.
  defp now_ms, do: Clock.System.now_ms()

  defp dispatch(peer, id, command), do: :erpc.call(peer, Router, :dispatch, [id, command])

  defp owner(peer, id), do: :erpc.call(peer, Router, :owner, [id])

  defp running?(peer, id), do: :erpc.call(peer, Registry, :lookup, [AuctionRegistry, id]) != []

  defp seqs(id) do
    Repo.all(from(e in EventRecord, where: e.auction_id == ^id, select: e.seq, order_by: e.seq))
  end

  defp open_auctions_with_bid(peer, ends_at) do
    config = %Config{
      title: "Failover lot",
      seller: "alice",
      starting_price: 1_000,
      reserve: nil,
      ends_at: ends_at,
      snipe_window_ms: 1_000,
      extension_ms: 1_000,
      max_extensions: 5
    }

    for _ <- 1..@auctions do
      {:ok, id} = Store.create_auction(config)

      assert {:accepted, %Bid{amount: 1_000}, %{seq: 2}} =
               dispatch(peer, id, {:place_bid, "req-bob", "bob", 1_000})

      id
    end
  end

  # By pigeonhole the busiest node owns at least a third of the auctions, so the
  # kill below always hits auctions regardless of how the ring hashed them.
  defp busiest_owner(peer, ids) do
    ids
    |> Enum.group_by(&owner(peer, &1))
    |> Enum.max_by(fn {_node, owned} -> length(owned) end)
  end

  test "survivors take over a killed node's auctions and keep its bids" do
    [first | _] = peers = start_cluster(3)
    ids = open_auctions_with_bid(first, now_ms() + 600_000)

    {victim, orphaned} = busiest_owner(first, ids)
    survivors = peers -- [victim]
    [survivor | _] = survivors

    for id <- orphaned, do: assert(running?(victim, id))

    kill_peer(victim)
    await_members(survivors)

    # Checked before any command is dispatched: takeover must not depend on traffic.
    for id <- orphaned do
      new_owner = owner(survivor, id)
      assert new_owner in survivors
      eventually(fn -> running?(new_owner, id) end)
    end

    for id <- ids do
      # A retry of a bid accepted before the kill gets its original outcome.
      assert {:duplicate, %Bid{request_id: "req-bob", amount: 1_000}, %{seq: 2}} =
               dispatch(survivor, id, {:place_bid, "req-bob", "bob", 1_000})

      # The rebuilt server still knows the high bid, so it enforces the minimum.
      assert {:rejected, {:below_minimum, _}} =
               dispatch(survivor, id, {:place_bid, "req-low", "carol", 1_000})

      assert {:accepted, %Bid{amount: 5_000}, %{seq: 3}} =
               dispatch(survivor, id, {:place_bid, "req-carol", "carol", 5_000})

      assert seqs(id) == [1, 2, 3]
    end
  end

  test "a survivor closes a killed node's auction exactly once when it comes due" do
    [first | _] = peers = start_cluster(3)
    ends_at = now_ms() + 5_000
    ids = open_auctions_with_bid(first, ends_at)

    {victim, _orphaned} = busiest_owner(first, ids)
    survivors = peers -- [victim]

    kill_peer(victim)

    # Otherwise the victim may have closed its auctions and nothing was taken over.
    assert now_ms() < ends_at, "setup outlasted the auctions, so the kill tested nothing"

    await_members(survivors)

    eventually(fn -> Store.open_auction_ids() == [] end, 15_000)

    # Once every server has stopped, nothing is left that could append a second close.
    for peer <- survivors do
      eventually(fn -> :erpc.call(peer, Registry, :count, [AuctionRegistry]) == 0 end)
    end

    for id <- ids do
      {:ok, events} = Store.load(id)

      assert [%{winner: %Bid{bidder: "bob", amount: 1_000}}] =
               Enum.filter(events, &(&1.type == :closed))

      assert List.last(events).type == :closed
      assert seqs(id) == Enum.to_list(1..length(events))
    end
  end
end
