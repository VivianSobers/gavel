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
  Appends events for an auction starting at `expected_seq + 1` in one transaction.
  Returns `{:ok, new_seq}` on success or `{:error, :conflict}` on a unique violation on the primary key.
  """
  @spec append(binary(), integer(), [Event.t()]) :: {:ok, integer()} | {:error, :conflict}
  def append(auction_id, expected_seq, events) do
    Repo.transaction(fn ->
      events
      |> Enum.with_index(expected_seq + 1)
      |> Enum.each(fn {event, seq} ->
        {type, payload, request_id} = Codec.encode(event)

        Repo.insert!(%EventRecord{
          auction_id: auction_id,
          seq: seq,
          type: type,
          payload: payload,
          request_id: request_id
        })
      end)

      expected_seq + length(events)
    end)
  rescue
    e in Ecto.ConstraintError ->
      if e.type == :unique and e.constraint == "events_pkey" do
        {:error, :conflict}
      else
        reraise e, __STACKTRACE__
      end
  end

  @doc """
  Loads events for an auction ordered by sequence number.
  """
  @spec load(binary()) :: {:ok, [Event.t()]} | {:error, :not_found}
  def load(auction_id) do
    with {:ok, valid_id} <- Ecto.UUID.cast(auction_id),
         true <- Repo.exists?(from(a in AuctionRecord, where: a.id == ^valid_id)) do
      records =
        Repo.all(
          from(e in EventRecord,
            where: e.auction_id == ^valid_id,
            order_by: [asc: e.seq]
          )
        )

      events = Enum.map(records, &Codec.decode(&1.type, &1.payload))
      {:ok, events}
    else
      _ -> {:error, :not_found}
    end
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
