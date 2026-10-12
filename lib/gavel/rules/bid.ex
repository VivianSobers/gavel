defmodule Gavel.Rules.Bid do
  @moduledoc """
  Auction bid struct and conversion to/from Gleam values.
  """

  defstruct [:request_id, :bidder, :amount, :at]

  @type t :: %__MODULE__{
          request_id: String.t(),
          bidder: String.t(),
          amount: integer(),
          at: integer()
        }

  @doc false
  def to_gleam(%__MODULE__{request_id: request_id, bidder: bidder, amount: amount, at: at}) do
    {:bid, request_id, bidder, amount, at}
  end

  @doc false
  def from_gleam({:bid, request_id, bidder, amount, at}) do
    %__MODULE__{
      request_id: request_id,
      bidder: bidder,
      amount: amount,
      at: at
    }
  end
end
