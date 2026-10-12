defmodule Gavel.Rules.Config do
  @moduledoc """
  Auction configuration struct and conversion to/from Gleam values.
  """

  defstruct [
    :title,
    :seller,
    :starting_price,
    :reserve,
    :ends_at,
    :snipe_window_ms,
    :extension_ms,
    :max_extensions
  ]

  @type t :: %__MODULE__{
          title: String.t(),
          seller: String.t(),
          starting_price: integer(),
          reserve: integer() | nil,
          ends_at: integer(),
          snipe_window_ms: integer(),
          extension_ms: integer(),
          max_extensions: integer()
        }

  @doc false
  def to_gleam(%__MODULE__{} = config) do
    reserve =
      case config.reserve do
        nil -> :none
        val when is_integer(val) -> {:some, val}
      end

    {:config, config.title, config.seller, config.starting_price, reserve, config.ends_at,
     config.snipe_window_ms, config.extension_ms, config.max_extensions}
  end

  @doc false
  def from_gleam(
        {:config, title, seller, starting_price, reserve, ends_at, snipe_window_ms, extension_ms,
         max_extensions}
      ) do
    reserve =
      case reserve do
        :none -> nil
        {:some, val} -> val
      end

    %__MODULE__{
      title: title,
      seller: seller,
      starting_price: starting_price,
      reserve: reserve,
      ends_at: ends_at,
      snipe_window_ms: snipe_window_ms,
      extension_ms: extension_ms,
      max_extensions: max_extensions
    }
  end
end
