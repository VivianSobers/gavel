defmodule Gavel.Rules do
  @moduledoc """
  Elixir boundary wrapper for the Gleam rules core.
  """

  alias Gavel.Rules.Config
  alias Gavel.Rules.Event

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
