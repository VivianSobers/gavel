defmodule Gavel.Cluster.Membership do
  @moduledoc """
  Tracks cluster node membership, maintains the consistent-hash ring,
  and broadcasts membership changes.
  """

  use GenServer

  alias Gavel.Cluster.Ring

  @pubsub Gavel.PubSub
  @cluster_topic "cluster"
  @ring_key {Gavel.Cluster, :ring}

  @doc """
  Starts the membership tracker GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Returns the current hash ring from `:persistent_term`, or `:ring_override` if set.
  """
  def ring do
    case Application.get_env(:gavel, :ring_override) do
      nil -> :persistent_term.get(@ring_key)
      override -> override
    end
  end

  @doc """
  Returns the sorted list of current cluster member nodes.
  """
  def members do
    GenServer.call(__MODULE__, :members)
  end

  @impl true
  def init(_opts) do
    if Node.alive?() do
      :net_kernel.monitor_nodes(true)
    end

    members = initial_members()
    ring = Ring.new(members)
    :persistent_term.put(@ring_key, ring)

    {:ok, %{members: MapSet.new(members)}}
  end

  @impl true
  def handle_call(:members, _from, state) do
    {:reply, Enum.sort(state.members), state}
  end

  @impl true
  def handle_info({:nodeup, node}, state) do
    new_members = MapSet.put(state.members, node)
    update_ring_and_broadcast(new_members, state)
  end

  @impl true
  def handle_info({:nodedown, node}, state) do
    new_members = MapSet.delete(state.members, node)
    update_ring_and_broadcast(new_members, state)
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp update_ring_and_broadcast(members_set, state) do
    sorted_members = Enum.sort(members_set)
    ring = Ring.new(sorted_members)
    :persistent_term.put(@ring_key, ring)

    Phoenix.PubSub.local_broadcast(@pubsub, @cluster_topic, {:membership_changed, sorted_members})

    {:noreply, %{state | members: members_set}}
  end

  defp initial_members do
    [node() | Node.list()]
    |> Enum.uniq()
    |> Enum.sort()
  end
end
