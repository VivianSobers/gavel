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

  Starts local servers for open auctions owned by node() that are not running yet,
  and stops local servers whose owner is another node.
  """
  @spec reconcile() :: %{started: [binary()], stopped: [binary()]}
  def reconcile do
    current_node = node()
    ring = Membership.ring()

    stopped =
      for {_, pid, _, _} <- DynamicSupervisor.which_children(Gavel.Auction.Supervisor),
          is_pid(pid),
          auction_id <- Registry.keys(Gavel.Auction.Registry, pid),
          Ring.owner(ring, auction_id) != current_node,
          match?(:ok, DynamicSupervisor.terminate_child(Gavel.Auction.Supervisor, pid)) do
        auction_id
      end

    started =
      for id <- Store.open_auction_ids(),
          Ring.owner(ring, id) == current_node,
          not running?(id),
          match?({:ok, _pid}, Local.ensure_started(id)),
          do: id

    %{started: started, stopped: stopped}
  end

  defp running?(auction_id) do
    case Registry.lookup(Gavel.Auction.Registry, auction_id) do
      [{pid, _}] -> Process.alive?(pid)
      [] -> false
    end
  end
end
