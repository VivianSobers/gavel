defmodule GavelWeb.AuctionLive.Index do
  @moduledoc """
  Lists open auctions and keeps their prices current.
  """

  use GavelWeb, :live_view

  alias Gavel.Auction.Server
  alias Gavel.Router
  alias Gavel.Store
  alias GavelWeb.Format

  @max_concurrent_loads 16
  @load_timeout_ms 25_000

  @impl true
  def mount(_params, _session, socket) do
    socket = assign(socket, page_title: "Auctions", auctions: %{}, all_loaded: false)

    if connected?(socket) do
      Phoenix.PubSub.subscribe(Gavel.PubSub, Server.auctions_topic())
      {:ok, load_auctions(socket)}
    else
      {:ok, socket}
    end
  end

  # Closed auctions stay in the map, hidden when rendering, so their sequence
  # numbers still turn away late updates from another server.
  @impl true
  def handle_info({:auction_updated, id, view}, socket) do
    {:noreply,
     update(socket, :auctions, &Map.update(&1, id, view, fn old -> newer(old, view) end))}
  end

  @impl true
  def render(assigns) do
    assigns = assign(assigns, :open, open_auctions(assigns.auctions))

    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Auctions
        <:actions>
          <.button navigate={~p"/auctions/new"} variant="primary">New auction</.button>
        </:actions>
      </.header>

      <p :if={@all_loaded and @open == []} class="text-base-content/70">
        No open auctions.
      </p>

      <ul id="auctions" class="divide-y divide-base-300">
        <li
          :for={{id, auction} <- @open}
          id={"auction-#{id}"}
          class="flex items-center justify-between gap-4 py-3"
        >
          <.link navigate={~p"/auctions/#{id}"} class="font-medium hover:underline">
            {auction.title}
          </.link>
          <span class="tabular-nums">{Format.money(price(auction))}</span>
        </li>
      </ul>
    </Layouts.app>
    """
  end

  defp load_auctions(socket) do
    results =
      Store.open_auction_ids()
      |> Task.async_stream(&{&1, Router.dispatch(&1, :view)},
        max_concurrency: @max_concurrent_loads,
        timeout: @load_timeout_ms,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    auctions = for {:ok, {id, {:view, view}}} <- results, into: %{}, do: {id, view}
    all_loaded = map_size(auctions) == length(results)
    socket = assign(socket, auctions: auctions, all_loaded: all_loaded)

    if all_loaded do
      socket
    else
      put_flash(socket, :error, "Some auctions are unavailable right now.")
    end
  end

  defp newer(old, new), do: if(new.seq > old.seq, do: new, else: old)

  defp open_auctions(auctions) do
    auctions
    |> Enum.filter(fn {_id, view} -> view.status == :open end)
    |> Enum.sort_by(fn {_id, view} -> view.ends_at end)
  end

  defp price(%{high_bid: nil, minimum_next_bid: minimum}), do: minimum
  defp price(%{high_bid: high_bid}), do: high_bid.amount
end
