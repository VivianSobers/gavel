defmodule Gavel.Rules.Event do
  @moduledoc """
  Auction event struct and conversion to/from Gleam values.
  """

  alias Gavel.Rules.Bid
  alias Gavel.Rules.Config

  defstruct [:type, :config, :bid, :ends_at, :winner]

  @type t :: %__MODULE__{
          type: :opened | :bid_accepted | :extended | :closed,
          config: Config.t() | nil,
          bid: Bid.t() | nil,
          ends_at: integer() | nil,
          winner: Bid.t() | nil
        }

  @doc false
  def to_gleam(%__MODULE__{type: :opened, config: %Config{} = config}) do
    {:opened, Config.to_gleam(config)}
  end

  def to_gleam(%__MODULE__{type: :bid_accepted, bid: %Bid{} = bid}) do
    {:bid_accepted, Bid.to_gleam(bid)}
  end

  def to_gleam(%__MODULE__{type: :extended, ends_at: ends_at}) when is_integer(ends_at) do
    {:extended, ends_at}
  end

  def to_gleam(%__MODULE__{type: :closed, winner: winner}) do
    gleam_winner =
      case winner do
        nil -> :none
        %Bid{} = bid -> {:some, Bid.to_gleam(bid)}
      end

    {:auction_closed, gleam_winner}
  end

  @doc false
  def from_gleam({:opened, gleam_config}) do
    %__MODULE__{
      type: :opened,
      config: Config.from_gleam(gleam_config)
    }
  end

  def from_gleam({:bid_accepted, gleam_bid}) do
    %__MODULE__{
      type: :bid_accepted,
      bid: Bid.from_gleam(gleam_bid)
    }
  end

  def from_gleam({:extended, ends_at}) when is_integer(ends_at) do
    %__MODULE__{
      type: :extended,
      ends_at: ends_at
    }
  end

  def from_gleam({:auction_closed, gleam_winner}) do
    winner =
      case gleam_winner do
        :none -> nil
        {:some, gleam_bid} -> Bid.from_gleam(gleam_bid)
      end

    %__MODULE__{
      type: :closed,
      winner: winner
    }
  end
end
