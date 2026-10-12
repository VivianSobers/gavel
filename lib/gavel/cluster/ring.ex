defmodule Gavel.Cluster.Ring do
  @moduledoc """
  Consistent-hash ring mapping auction IDs to cluster nodes.
  """

  @doc """
  Constructs a new hash ring containing the given nodes.
  """
  def new(nodes) do
    HashRing.new()
    |> HashRing.add_nodes(nodes)
  end

  @doc """
  Looks up the node responsible for the given auction ID.
  """
  def owner(ring, auction_id) do
    HashRing.key_to_node(ring, auction_id)
  end
end
