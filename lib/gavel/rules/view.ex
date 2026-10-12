defmodule Gavel.Rules.View do
  @moduledoc """
  Auction view struct projected from Gleam state.
  """

  alias Gavel.Rules.Bid

  defstruct [
    :title,
    :seller,
    :status,
    :high_bid,
    :recent_bids,
    :minimum_next_bid,
    :ends_at,
    :seq,
    :reserve_met
  ]

  @type t :: %__MODULE__{
          title: String.t() | nil,
          seller: String.t() | nil,
          status: :pending | :open | :closed,
          high_bid: Bid.t() | nil,
          recent_bids: [Bid.t()],
          minimum_next_bid: integer(),
          ends_at: integer(),
          seq: integer(),
          reserve_met: boolean()
        }

  @doc false
  @spec from_gleam(any()) :: t()
  def from_gleam(
        {:state, config, status, high_bid, bids, _accepted, _extensions_used, ends_at, seq} =
          state
      ) do
    {title, seller, reserve} = unpack_config(config)

    %__MODULE__{
      title: title,
      seller: seller,
      status: status,
      high_bid: unpack_bid(high_bid),
      recent_bids: bids |> Enum.take(20) |> Enum.map(&Bid.from_gleam/1),
      minimum_next_bid: :gavel_rules@auction.minimum_next_bid(state),
      ends_at: ends_at,
      seq: seq,
      reserve_met: reserve_met?(reserve, high_bid)
    }
  end

  defp unpack_config(
         {:some,
          {:config, title, seller, _starting_price, reserve, _ends_at, _snipe, _ext, _max_ext}}
       ) do
    {title, seller, reserve}
  end

  defp unpack_config(:none) do
    {nil, nil, :none}
  end

  defp unpack_bid({:some, gleam_bid}), do: Bid.from_gleam(gleam_bid)
  defp unpack_bid(:none), do: nil

  defp reserve_met?(:none, _high_bid), do: true

  defp reserve_met?({:some, reserve_cents}, {:some, {:bid, _id, _bidder, amount, _at}}) do
    amount >= reserve_cents
  end

  defp reserve_met?({:some, _reserve_cents}, :none), do: false
end
