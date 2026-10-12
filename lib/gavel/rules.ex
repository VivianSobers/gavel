defmodule Gavel.Rules do
  @moduledoc """
  Elixir boundary wrapper for the Gleam rules core.
  """

  alias Gavel.Rules.Bid
  alias Gavel.Rules.Config
  alias Gavel.Rules.Event
  alias Gavel.Rules.View

  @type command :: {:place_bid, String.t(), String.t(), integer()} | :close

  @type rejection ::
          {:invalid_config, String.t()}
          | :not_open
          | :already_closed
          | :too_late
          | {:below_minimum, integer()}
          | :invalid_amount
          | :seller_cannot_bid
          | :already_high_bidder
          | :not_yet_ended

  @type history_error ::
          {:rejected, pos_integer(), rejection()}
          | {:unexpected, pos_integer()}
          | :missing_opened

  @doc """
  Validates an auction config and returns the initial Opened event.
  """
  @spec open(Config.t()) :: {:ok, [Event.t()]} | {:error, rejection()}
  def open(%Config{} = config) do
    gleam_config = Config.to_gleam(config)

    case :gavel_rules@auction.open(gleam_config) do
      {:ok, gleam_events} ->
        {:ok, Enum.map(gleam_events, &Event.from_gleam/1)}

      {:error, rejection} ->
        {:error, from_gleam_rejection(rejection)}
    end
  end

  @doc """
  Folds a list of events into an opaque auction state.
  """
  @spec fold([Event.t()]) :: any()
  def fold(events) when is_list(events) do
    gleam_events = Enum.map(events, &Event.to_gleam/1)
    :gavel_rules@auction.fold(gleam_events)
  end

  @doc """
  Evolves an opaque auction state by applying a single event.
  """
  @spec evolve(any(), Event.t()) :: any()
  def evolve(state, %Event{} = event) do
    gleam_event = Event.to_gleam(event)
    :gavel_rules@auction.evolve(state, gleam_event)
  end

  @doc """
  Decides a command against an opaque auction state at the given unix timestamp in ms.
  """
  @spec decide(any(), command(), integer()) ::
          {:emit, [Event.t()]} | {:duplicate, Bid.t()} | {:error, rejection()}
  def decide(state, command, now_ms) when is_integer(now_ms) do
    gleam_command = to_gleam_command(command)

    case :gavel_rules@auction.decide(state, gleam_command, now_ms) do
      {:ok, {:emit, gleam_events}} ->
        {:emit, Enum.map(gleam_events, &Event.from_gleam/1)}

      {:ok, {:duplicate, gleam_bid}} ->
        {:duplicate, Bid.from_gleam(gleam_bid)}

      {:error, rejection} ->
        {:error, from_gleam_rejection(rejection)}
    end
  end

  @doc """
  Projects an opaque auction state into a View struct.
  """
  @spec view(any()) :: View.t()
  def view(state) do
    View.from_gleam(state)
  end

  @doc """
  Validates a stored history of events and returns the final View struct.
  """
  @spec validate_history([Event.t()]) :: {:ok, View.t()} | {:error, history_error()}
  def validate_history(events) when is_list(events) do
    gleam_events = Enum.map(events, &Event.to_gleam/1)

    case :gavel_rules@history.validate(gleam_events) do
      {:ok, gleam_state} ->
        {:ok, View.from_gleam(gleam_state)}

      {:error, {:rejected, seq, gleam_rejection}} ->
        {:error, {:rejected, seq, from_gleam_rejection(gleam_rejection)}}

      {:error, {:unexpected, seq}} ->
        {:error, {:unexpected, seq}}

      {:error, :missing_opened} ->
        {:error, :missing_opened}
    end
  end

  defp to_gleam_command({:place_bid, request_id, bidder, amount})
       when is_binary(request_id) and is_binary(bidder) and is_integer(amount) do
    {:place_bid, request_id, bidder, amount}
  end

  defp to_gleam_command(:close), do: :close

  @doc false
  @spec from_gleam_rejection(any()) :: rejection()
  def from_gleam_rejection({:invalid_config, field}) when is_binary(field),
    do: {:invalid_config, field}

  def from_gleam_rejection(:not_open), do: :not_open
  def from_gleam_rejection(:already_closed), do: :already_closed
  def from_gleam_rejection(:too_late), do: :too_late

  def from_gleam_rejection({:below_minimum, cents}) when is_integer(cents),
    do: {:below_minimum, cents}

  def from_gleam_rejection(:invalid_amount), do: :invalid_amount
  def from_gleam_rejection(:seller_cannot_bid), do: :seller_cannot_bid
  def from_gleam_rejection(:already_high_bidder), do: :already_high_bidder
  def from_gleam_rejection(:not_yet_ended), do: :not_yet_ended
end
