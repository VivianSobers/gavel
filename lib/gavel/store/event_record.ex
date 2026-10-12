defmodule Gavel.Store.EventRecord do
  @moduledoc false

  use Ecto.Schema

  @primary_key false
  schema "events" do
    field :auction_id, :binary_id, primary_key: true
    field :seq, :integer, primary_key: true
    field :type, :string
    field :payload, :map
    field :request_id, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
