defmodule Gavel.Cluster.Placement do
  @moduledoc """
  Reconciles auction server placement across cluster nodes.
  """

  use GenServer

  alias Gavel.Auction.Local
  alias Gavel.Cluster.Membership
  alias Gavel.Cluster.Ring
  alias Gavel.Store

  @pubsub Gavel.PubSub
  @cluster_topic "cluster"
  @default_interval_ms 5_000

  @doc """
  Starts the placement reconciler GenServer.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

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

    result = %{started: started, stopped: stopped}

    :telemetry.execute(
      [:gavel, :placement, :reconcile],
      %{started: length(started), stopped: length(stopped)},
      result
    )

    result
  end

  @impl true
  def init(opts) do
    Phoenix.PubSub.subscribe(@pubsub, @cluster_topic)

    interval_ms =
      Keyword.get(
        opts,
        :placement_interval_ms,
        Application.get_env(:gavel, :placement_interval_ms, @default_interval_ms)
      )

    schedule_reconcile(interval_ms)

    {:ok, %{interval_ms: interval_ms}}
  end

  @impl true
  def handle_info({:membership_changed, _members}, state) do
    reconcile()
    {:noreply, state}
  end

  @impl true
  def handle_info(:reconcile, state) do
    reconcile()
    schedule_reconcile(state.interval_ms)
    {:noreply, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  defp schedule_reconcile(interval_ms) when is_integer(interval_ms) and interval_ms > 0 do
    Process.send_after(self(), :reconcile, interval_ms)
  end

  # A zero interval (the test configuration) disables periodic reconciles.
  defp schedule_reconcile(_), do: nil

  defp running?(auction_id) do
    case Registry.lookup(Gavel.Auction.Registry, auction_id) do
      [{pid, _}] -> Process.alive?(pid)
      [] -> false
    end
  end
end
