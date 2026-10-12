defmodule Gavel.Store do
  @moduledoc """
  Persistence layer for auctions and events backed by PostgreSQL.
  """

  import Ecto.Query

  alias Gavel.Repo
  alias Gavel.Rules
  alias Gavel.Rules.Config
  alias Gavel.Rules.Event
  alias Gavel.Store.AuctionRecord
  alias Gavel.Store.Codec
  alias Gavel.Store.EventRecord

  @doc """
  Validates an auction config with rules and persists the auction row and opened event at sequence 1.
  """
  @spec create_auction(Config.t()) :: {:ok, binary()} | {:error, Rules.rejection()}
  def create_auction(%Config{} = config) do
    with {:ok, [opened_event]} <- Rules.open(config) do
      insert_auction_and_opened(config, opened_event)
    end
  end

  @doc """
  Loads events for an auction.
  """
  @spec load(binary()) :: {:ok, [Event.t()]}
  def load(auction_id) do
    records =
      Repo.all(
        from(e in EventRecord,
          where: e.auction_id == ^auction_id
        )
      )

    events = Enum.map(records, &Codec.decode(&1.type, &1.payload))
    {:ok, events}
  end

  defp insert_auction_and_opened(%Config{} = config, %Event{} = opened_event) do
    {type, payload, request_id} = Codec.encode(opened_event)

    Repo.transaction(fn ->
      auction =
        Repo.insert!(%AuctionRecord{
          title: config.title,
          seller: config.seller,
          config: payload,
          ends_at: DateTime.from_unix!(config.ends_at * 1_000, :microsecond)
        })

      Repo.insert!(%EventRecord{
        auction_id: auction.id,
        seq: 1,
        type: type,
        payload: payload,
        request_id: request_id
      })

      auction.id
    end)
  end
end
