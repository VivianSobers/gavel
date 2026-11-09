defmodule GavelWeb.AuctionLive.Show do
  @moduledoc """
  Live view of one auction: its bid ladder, countdown and bid form.
  """

  use GavelWeb, :live_view

  alias Gavel.Auction.Server
  alias Gavel.Clock
  alias Gavel.Router
  alias GavelWeb.Format

  @tick_ms 1_000

  @impl true
  def mount(%{"id" => raw_id}, _session, socket) do
    # Servers and topics are keyed by the id's exact text, so only its canonical
    # form may reach them.
    case Ecto.UUID.cast(raw_id) do
      {:ok, id} -> mount_auction(id, socket)
      :error -> {:ok, leave(socket, "That auction does not exist.")}
    end
  end

  defp mount_auction(id, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Gavel.PubSub, Server.auction_topic(id))
      schedule_tick()
    end

    case Router.dispatch(id, :view) do
      {:view, view} ->
        {:ok,
         assign(socket,
           page_title: view.title,
           auction_id: id,
           view: view,
           now: Clock.now_ms(),
           request_id: new_request_id(),
           form: bid_form("", "")
         )}

      {:error, :not_found} ->
        {:ok, leave(socket, "That auction does not exist.")}

      {:error, _reason} ->
        {:ok, leave(socket, "That auction is unavailable right now.")}
    end
  end

  @impl true
  def handle_event("bid", %{"bid" => %{"bidder" => bidder, "amount" => amount}}, socket) do
    socket = socket |> clear_flash() |> assign(form: bid_form(bidder, amount))
    name = String.trim(bidder)

    case validate_bid(name, amount) do
      {:ok, cents} ->
        command = {:place_bid, socket.assigns.request_id, name, cents}
        {:noreply, apply_reply(socket, Router.dispatch(socket.assigns.auction_id, command))}

      {:error, message} ->
        {:noreply, put_flash(socket, :error, message)}
    end
  end

  @impl true
  def handle_info({:auction_event, _id, _event, view}, socket) do
    {:noreply, put_view(socket, view)}
  end

  def handle_info(:tick, socket) do
    if socket.assigns.view.status == :open, do: schedule_tick()
    {:noreply, socket |> assign(now: Clock.now_ms()) |> refresh_if_overdue()}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        {@view.title}
        <:subtitle>Sold by {@view.seller}</:subtitle>
      </.header>

      <p id="auction-status" class="text-lg font-semibold">
        {status_line(@view, @now)}
      </p>

      <.form :if={@view.status == :open} for={@form} id="bid-form" phx-submit="bid">
        <p class="text-sm text-base-content/70">
          Minimum bid {Format.money(@view.minimum_next_bid)}
        </p>
        <.input field={@form[:bidder]} label="Your name" autocomplete="name" />
        <.input field={@form[:amount]} label="Amount ($)" inputmode="decimal" />
        <.button variant="primary" phx-disable-with="Placing...">Place bid</.button>
      </.form>

      <h2 class="text-sm font-semibold">Bids</h2>
      <p :if={@view.recent_bids == []} class="text-base-content/70">No bids yet.</p>
      <ol id="bid-ladder" class="divide-y divide-base-300">
        <li :for={bid <- @view.recent_bids} class="flex justify-between gap-4 py-2">
          <span>{bid.bidder}</span>
          <span class="tabular-nums">{Format.money(bid.amount)}</span>
        </li>
      </ol>
    </Layouts.app>
    """
  end

  defp leave(socket, message) do
    socket |> put_flash(:error, message) |> push_navigate(to: ~p"/")
  end

  defp schedule_tick, do: Process.send_after(self(), :tick, @tick_ms)

  # A node can die between committing the close and broadcasting it, so a page
  # past the end time asks instead of waiting for an event that may never come.
  defp refresh_if_overdue(%{assigns: %{view: %{status: :open} = view, now: now}} = socket)
       when now >= view.ends_at do
    case Router.dispatch(socket.assigns.auction_id, :view) do
      {:view, latest} -> put_view(socket, latest)
      _unavailable -> socket
    end
  end

  defp refresh_if_overdue(socket), do: socket

  # The request id is kept until the outcome is known, so resubmitting from this
  # page after an unconfirmed bid cannot place it twice. A reload starts afresh.
  defp new_request_id, do: Ecto.UUID.generate()

  defp bid_form(bidder, amount) do
    to_form(%{"bidder" => bidder, "amount" => amount}, as: :bid)
  end

  defp validate_bid("", _amount), do: {:error, "Enter your name."}

  defp validate_bid(_name, amount) do
    with :error <- Format.parse_money(amount) do
      {:error, "Enter a dollar amount."}
    end
  end

  defp apply_reply(socket, {:accepted, _bid, view}) do
    socket |> put_view(view) |> finish_request() |> put_flash(:info, "Bid placed.")
  end

  defp apply_reply(socket, {:duplicate, bid, view}) do
    socket
    |> put_view(view)
    |> finish_request()
    |> put_flash(:info, "Your bid of #{Format.money(bid.amount)} was already placed.")
  end

  defp apply_reply(socket, {:rejected, reason}) do
    socket |> finish_request() |> put_flash(:error, rejection_message(reason))
  end

  defp apply_reply(socket, {:error, _reason}) do
    put_flash(socket, :error, "We could not confirm your bid. It is safe to try again.")
  end

  defp finish_request(socket) do
    bidder = socket.assigns.form[:bidder].value
    assign(socket, request_id: new_request_id(), form: bid_form(bidder, ""))
  end

  defp put_view(socket, view) do
    if view.seq > socket.assigns.view.seq, do: assign(socket, view: view), else: socket
  end

  defp status_line(%{status: :open, ends_at: ends_at}, now) when now >= ends_at do
    "Closing..."
  end

  defp status_line(%{status: :open, ends_at: ends_at}, now) do
    "Ends in #{Format.remaining(ends_at - now)}"
  end

  defp status_line(%{high_bid: nil}, _now), do: "No bids"
  defp status_line(%{reserve_met: false}, _now), do: "Reserve not met"

  defp status_line(%{high_bid: bid}, _now) do
    "Won by #{bid.bidder} for #{Format.money(bid.amount)}"
  end

  defp rejection_message({:below_minimum, cents}) do
    "Your bid must be at least #{Format.money(cents)}."
  end

  defp rejection_message(:too_late), do: "This auction has ended."
  defp rejection_message(:already_closed), do: "This auction has ended."
  defp rejection_message(:seller_cannot_bid), do: "You cannot bid on your own auction."
  defp rejection_message(:already_high_bidder), do: "You are already the high bidder."
  defp rejection_message(:invalid_amount), do: "Enter an amount above zero."
  defp rejection_message(:not_open), do: "This auction is not open."
end
