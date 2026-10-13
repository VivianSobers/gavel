defmodule Gavel.Cluster.Placement do
  @moduledoc """
  Reconciles auction server placement across cluster nodes.
  """

  alias Gavel.Auction.Local
  alias Gavel.Cluster.Membership
  alias Gavel.Cluster.Ring
  alias Gavel.Store

  @doc """
  Reconciles auction placement on the local node.

  Starts local servers for open auctions owned by node() that are not running yet.
  """
  @spec reconcile() :: %{started: [binary()], stopped: [binary()]}
  def reconcile do
    current_node = node()
    ring = Membership.ring()

    started =
      for id <- Store.open_auction_ids(),
          Ring.owner(ring, id) == current_node,
          not running?(id),
          match?({:ok, _pid}, Local.ensure_started(id)),
          do: id

    %{started: started, stopped: []}
  end

  defp running?(auction_id), do: Registry.lookup(Gavel.Auction.Registry, auction_id) != []
end
