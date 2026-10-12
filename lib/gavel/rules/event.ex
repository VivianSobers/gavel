defmodule Gavel.Rules.Event do
  @moduledoc """
  Auction event struct and conversion to/from Gleam values.
  """

  alias Gavel.Rules.Config

  defstruct [:type, :config, :bid, :ends_at, :winner]

  @type t :: %__MODULE__{
          type: :opened | :bid_accepted | :extended | :closed,
          config: Config.t() | nil,
          bid: any() | nil,
          ends_at: integer() | nil,
          winner: any() | nil
        }

  @doc false
  def from_gleam({:opened, gleam_config}) do
    %__MODULE__{
      type: :opened,
      config: Config.from_gleam(gleam_config)
    }
  end
end
