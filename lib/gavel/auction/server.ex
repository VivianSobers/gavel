defmodule Gavel.Auction.Server do
  @moduledoc """
  GenServer process managing a single auction.
  """

  use GenServer, restart: :transient

  alias Gavel.Rules
  alias Gavel.Store

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
  def handle_call({:command, _command}, _from, state) do
    {:reply, :ok, state}
  end
end
