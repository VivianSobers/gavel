defmodule Gavel.Auction.Server do
  @moduledoc """
  GenServer process managing a single auction.
  """

  use GenServer, restart: :transient

  alias Gavel.Clock
  alias Gavel.Rules
  alias Gavel.Store

  @pubsub Gavel.PubSub

  @doc """
  Starts an auction server registered in the registry under its auction id.
  """
  def start_link(auction_id) when is_binary(auction_id) do
    GenServer.start_link(__MODULE__, auction_id, name: via_tuple(auction_id))
  end

  @doc """
  Returns the Registry via tuple for the given auction id.
  """
  def via_tuple(auction_id) when is_binary(auction_id) do
    {:via, Registry, {Gavel.Auction.Registry, auction_id}}
  end

  @impl true
  def init(auction_id) do
    {:ok, %{auction_id: auction_id, rules_state: nil, view: nil}, {:continue, :load}}
  end

  @impl true
  def handle_continue(:load, %{auction_id: auction_id} = state) do
    case Store.load(auction_id) do
      {:ok, events} ->
        rules_state = Rules.fold(events)
        view = Rules.view(rules_state)
        {:noreply, %{state | rules_state: rules_state, view: view}}

      {:error, :not_found} ->
        {:stop, {:shutdown, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:command, {:place_bid, _, _, _} = cmd}, _from, state) do
    now = Clock.now_ms()
    place_bid(cmd, now, state)
  end

  def handle_call({:command, _command}, _from, state) do
    {:reply, :ok, state}
  end

  defp place_bid(cmd, now, %{auction_id: id, rules_state: rules_state, view: view} = state) do
    case Rules.decide(rules_state, cmd, now) do
      {:emit, events} ->
        case Store.append(id, view.seq, events) do
          {:ok, _new_seq} ->
            {new_rules_state, new_view} = apply_events(rules_state, events)
            broadcast_events(id, events, new_view)

            {:reply, {:accepted, new_view.high_bid, new_view},
             %{state | rules_state: new_rules_state, view: new_view}}

          {:error, :conflict} ->
            {:stop, :normal, {:error, :stale}, state}
        end

      {:error, rejection} ->
        {:reply, {:rejected, rejection}, state}
    end
  end

  defp apply_events(rules_state, events) do
    new_rules_state = Enum.reduce(events, rules_state, &Rules.evolve(&2, &1))
    {new_rules_state, Rules.view(new_rules_state)}
  end

  defp broadcast_events(id, events, view) do
    for event <- events do
      Phoenix.PubSub.broadcast(@pubsub, "auction:" <> id, {:auction_event, id, event, view})
    end

    Phoenix.PubSub.broadcast(@pubsub, "auctions", {:auction_updated, id, view})
  end
end
