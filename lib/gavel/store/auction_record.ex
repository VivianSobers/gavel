defmodule Gavel.Store.AuctionRecord do
  @moduledoc false

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "auctions" do
    field :title, :string
    field :seller, :string
    field :config, :map
    field :ends_at, :utc_datetime_usec
    field :closed_at, :utc_datetime_usec

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
