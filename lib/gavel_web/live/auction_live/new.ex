defmodule GavelWeb.AuctionLive.New do
  @moduledoc """
  Form for opening a new auction.
  """

  use GavelWeb, :live_view

  alias Gavel.Auction.Server
  alias Gavel.Clock
  alias Gavel.Router
  alias Gavel.Rules.Config
  alias Gavel.Store
  alias GavelWeb.Format

  @snipe_window_ms 30_000
  @extension_ms 30_000
  @max_extensions 10
  @max_minutes 525_600

  @fields %{
    "title" => "",
    "seller" => "",
    "starting_price" => "",
    "reserve" => "",
    "duration_minutes" => "60"
  }

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "New auction", form: to_form(@fields, as: :auction))}
  end

  @impl true
  def handle_event("save", %{"auction" => params}, socket) do
    with {:ok, config} <- build_config(params),
         {:ok, id} <- Store.create_auction(config) do
      announce(id)
      {:noreply, push_navigate(socket, to: ~p"/auctions/#{id}")}
    else
      {:error, reason} ->
        {:noreply,
         socket
         |> assign(form: to_form(params, as: :auction))
         |> put_flash(:error, message(reason))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>New auction</.header>

      <.form for={@form} id="auction-form" phx-submit="save">
        <.input field={@form[:title]} label="Title" />
        <.input field={@form[:seller]} label="Seller" />
        <.input field={@form[:starting_price]} label="Starting price ($)" inputmode="decimal" />
        <.input field={@form[:reserve]} label="Reserve ($, optional)" inputmode="decimal" />
        <.input field={@form[:duration_minutes]} label="Duration (minutes)" inputmode="numeric" />
        <.button variant="primary" phx-disable-with="Opening...">Open auction</.button>
      </.form>
    </Layouts.app>
    """
  end

  # A new auction has no committed event yet, so nothing else tells open lists.
  defp announce(id) do
    with {:view, view} <- Router.dispatch(id, :view) do
      Server.announce(id, view)
    end
  end

  defp build_config(params) do
    with {:ok, starting_price} <- money(params["starting_price"], "Starting price"),
         {:ok, reserve} <- optional_money(params["reserve"]),
         {:ok, minutes} <- minutes(params["duration_minutes"]) do
      {:ok,
       %Config{
         title: String.trim(params["title"]),
         seller: String.trim(params["seller"]),
         starting_price: starting_price,
         reserve: reserve,
         ends_at: Clock.now_ms() + minutes * 60_000,
         snipe_window_ms: @snipe_window_ms,
         extension_ms: @extension_ms,
         max_extensions: @max_extensions
       }}
    end
  end

  defp money(input, label) do
    with :error <- Format.parse_money(input) do
      {:error, "#{label} must be a dollar amount."}
    end
  end

  defp optional_money(input) do
    if String.trim(input) == "", do: {:ok, nil}, else: money(input, "Reserve")
  end

  defp minutes(input) do
    case Integer.parse(String.trim(input)) do
      {minutes, ""} when minutes in 1..@max_minutes -> {:ok, minutes}
      _ -> {:error, "Duration must be a whole number of minutes, up to one year."}
    end
  end

  defp message({:invalid_config, field}), do: "Check the #{String.replace(field, "_", " ")}."
  defp message(text) when is_binary(text), do: text
end
