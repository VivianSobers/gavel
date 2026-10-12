defmodule Gavel.Rules do
  @moduledoc """
  Elixir boundary wrapper for the Gleam rules core.
  """

  alias Gavel.Rules.Config
  alias Gavel.Rules.Event

  @doc """
  Validates an auction config and returns the initial Opened event.
  """
  @spec open(Config.t()) :: {:ok, [Event.t()]} | {:error, any()}
  def open(%Config{} = config) do
    gleam_config = Config.to_gleam(config)

    with {:ok, gleam_events} <- :gavel_rules@auction.open(gleam_config) do
      {:ok, Enum.map(gleam_events, &Event.from_gleam/1)}
    end
  end
end
