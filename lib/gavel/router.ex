defmodule Gavel.Router do
  @moduledoc """
  Routes auction commands to the node that owns the auction.
  """

  alias Gavel.Cluster.Membership
  alias Gavel.Cluster.Ring

  @doc """
  Returns the cluster node currently owning the given auction ID.
  """
  def owner(auction_id) do
    Ring.owner(Membership.ring(), auction_id)
  end

  @doc """
  Dispatches a command to the owner node for the given auction ID.
  """
  def dispatch(auction_id, command) do
    rpc().call(owner(auction_id), Gavel.Auction.Local, :command, [auction_id, command], 5_000)
  end

  defp rpc do
    Application.get_env(:gavel, :rpc, Gavel.Cluster.Rpc)
  end
end
