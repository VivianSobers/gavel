defmodule Gavel.Auction.Server do
  @moduledoc """
  GenServer process managing a single auction.
  """

  use GenServer, restart: :transient

  alias Gavel.Clock
  alias Gavel.Rules
  alias Gavel.Rules.Event
  alias Gavel.Store

  @pubsub Gavel.PubSub
  @max_timer_ms 86_400_000

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
    {:ok,
     %{
       auction_id: auction_id,
       rules_state: nil,
       view: nil,
       timer_ref: nil,
       linger_ref: nil
     }, {:continue, :load}}
  end

  @impl true
  def handle_continue(:load, %{auction_id: auction_id} = state) do
    case Store.load(auction_id) do
      {:ok, events} ->
        rules_state = Rules.fold(events)
        view = Rules.view(rules_state)

        case close_if_due(%{state | rules_state: rules_state, view: view}, Clock.now_ms()) do
          {:ok, new_state, _events} ->
            {:noreply, new_state}

          {:scheduled, new_state} ->
            {:noreply, new_state}

          :stale ->
            {:stop, :normal, state}
        end

      {:error, :not_found} ->
        {:stop, {:shutdown, :not_found}, state}
    end
  end

  @impl true
  def handle_call({:command, :view}, _from, state), do: {:reply, {:view, state.view}, state}

  def handle_call({:command, command}, _from, state) do
    now = Clock.now_ms()

    case Rules.decide(state.rules_state, command, now) do
      {:emit, events} ->
        case commit(events, state) do
          {:ok, new_state} -> {:reply, reply(command, events, new_state.view), new_state}
          :stale -> {:stop, :normal, {:error, :stale}, state}
        end

      {:duplicate, bid} ->
        {:reply, {:duplicate, bid, state.view}, state}

      {:error, rejection} ->
        {:reply, {:rejected, rejection}, state}
    end
  end

  @impl true
  def handle_info(:close_due, %{view: %{status: :closed}} = state), do: {:noreply, state}

  def handle_info(:close_due, state) do
    case close_if_due(state, Clock.now_ms()) do
      {:ok, new_state, _events} -> {:noreply, new_state}
      {:scheduled, new_state} -> {:noreply, new_state}
      :stale -> {:stop, :normal, state}
    end
  end

  def handle_info(:linger_stop, %{view: %{status: :closed}} = state) do
    {:stop, :normal, state}
  end

  def handle_info(:linger_stop, state), do: {:noreply, state}

  defp close_if_due(state, now) do
    with true <- state.view.status == :open and now >= state.view.ends_at,
         {:emit, events} <- Rules.decide(state.rules_state, :close, now) do
      case commit(events, state) do
        {:ok, new_state} -> {:ok, new_state, events}
        :stale -> :stale
      end
    else
      _ -> {:scheduled, schedule_close_timer(state)}
    end
  end

  # Appends the decided events behind the sequence fence, then applies and
  # broadcasts them. `:stale` means another writer appended first.
  defp commit(events, %{auction_id: id, rules_state: rules_state, view: view} = state) do
    case Store.append(id, view.seq, events) do
      {:ok, _new_seq} ->
        {new_rules_state, new_view} = apply_events(rules_state, events)
        broadcast_events(id, events, new_view)
        {:ok, schedule_close_timer(%{state | rules_state: new_rules_state, view: new_view})}

      {:error, :conflict} ->
        :stale
    end
  end

  defp reply({:place_bid, _, _, _}, _events, view), do: {:accepted, view.high_bid, view}
  defp reply(:close, events, view), do: {:closed, find_winner(events), view}

  defp schedule_close_timer(%{timer_ref: timer_ref, view: %{status: :closed}} = state) do
    if timer_ref, do: Process.cancel_timer(timer_ref)
    linger_ref = schedule_linger(state)
    %{state | timer_ref: nil, linger_ref: linger_ref}
  end

  defp schedule_close_timer(%{timer_ref: timer_ref, view: %{ends_at: ends_at}} = state) do
    if timer_ref, do: Process.cancel_timer(timer_ref)
    # send_after rejects delays above 2^32 - 1 ms; a capped timer just re-checks.
    delay = ends_at |> Kernel.-(Clock.now_ms()) |> max(0) |> min(@max_timer_ms)
    %{state | timer_ref: Process.send_after(self(), :close_due, delay)}
  end

  defp schedule_linger(%{linger_ref: linger_ref}) when not is_nil(linger_ref), do: linger_ref

  defp schedule_linger(_state) do
    Process.send_after(self(), :linger_stop, linger_ms())
  end

  defp linger_ms do
    Application.get_env(:gavel, :linger_ms, 30_000)
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

  defp find_winner(events) do
    case Enum.find(events, &(&1.type == :closed)) do
      %Event{winner: winner} -> winner
      nil -> nil
    end
  end
end
