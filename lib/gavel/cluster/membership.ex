defmodule Gavel.Cluster.Membership do
  @moduledoc """
  Tracks cluster node membership, maintains the consistent-hash ring,
  and broadcasts membership changes.
  """

  use GenServer

  alias Gavel.Cluster.Ring

  @scope Gavel.Cluster
  @group :ring_members
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

  @doc """
  Leaves the ring members group.
  """
  def leave_ring do
    case Process.whereis(__MODULE__) do
      nil ->
        :ok

      pid ->
        case :pg.leave(@scope, @group, pid) do
          :ok -> :ok
          :not_joined -> :ok
        end
    end
  end

  @doc """
  Joins the ring members group.
  """
  def join_ring do
    case Process.whereis(__MODULE__) do
      nil -> :ok
      pid -> :pg.join(@scope, @group, pid)
    end
  end

  @impl true
  def init(_opts) do
    ring_member? = Application.get_env(:gavel, :ring_member, true)

    if ring_member? do
      :pg.join(@scope, @group, self())
    end

    {ref, pids} = :pg.monitor(@scope, @group)

    nodes = Enum.map(pids, &node/1)
    nodes = if ring_member?, do: [node() | nodes], else: nodes

    members =
      nodes
      |> Enum.uniq()
      |> Enum.sort()

    ring = Ring.new(members)
    :persistent_term.put(@ring_key, ring)

    {:ok, %{monitor_ref: ref, members: members}}
  end

  @impl true
  def handle_call(:members, _from, state) do
    {:reply, state.members, state}
  end

  @impl true
  def handle_info({ref, :join, :ring_members, _pids}, %{monitor_ref: ref} = state) do
    update_ring_and_broadcast(state)
  end

  @impl true
  def handle_info({ref, :leave, :ring_members, _pids}, %{monitor_ref: ref} = state) do
    update_ring_and_broadcast(state)
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp update_ring_and_broadcast(state) do
    members =
      @scope
      |> :pg.get_members(@group)
      |> Enum.map(&node/1)
      |> Enum.uniq()
      |> Enum.sort()

    ring = Ring.new(members)
    :persistent_term.put(@ring_key, ring)

    Phoenix.PubSub.local_broadcast(@pubsub, @cluster_topic, {:membership_changed, members})

    {:noreply, %{state | members: members}}
  end
end
