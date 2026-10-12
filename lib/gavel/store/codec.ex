defmodule Gavel.Store.Codec do
  @moduledoc """
  Encodes and decodes auction events to and from database JSON payloads.
  """

  alias Gavel.Rules.Bid
  alias Gavel.Rules.Config
  alias Gavel.Rules.Event

  @type type_string :: String.t()
  @type payload_map :: map()
  @type request_id :: String.t() | nil

  @spec encode(Event.t()) :: {type_string(), payload_map(), request_id()}
  def encode(%Event{type: :opened, config: %Config{} = config}) do
    {"opened", encode_config(config), nil}
  end

  def encode(%Event{type: :bid_accepted, bid: %Bid{} = bid}) do
    {"bid_accepted", encode_bid(bid), bid.request_id}
  end

  def encode(%Event{type: :extended, ends_at: ends_at}) when is_integer(ends_at) do
    {"extended", %{"ends_at" => ends_at}, nil}
  end

  def encode(%Event{type: :closed, winner: winner}) do
    payload = %{"winner" => if(winner, do: encode_bid(winner), else: nil)}
    {"closed", payload, nil}
  end

  @spec decode(type_string(), payload_map()) :: Event.t()
  def decode("opened", payload), do: %Event{type: :opened, config: decode_config(payload)}
  def decode("bid_accepted", payload), do: %Event{type: :bid_accepted, bid: decode_bid(payload)}
  def decode("extended", %{"ends_at" => ends_at}), do: %Event{type: :extended, ends_at: ends_at}
  def decode("closed", %{"winner" => nil}), do: %Event{type: :closed, winner: nil}

  def decode("closed", %{"winner" => winner}),
    do: %Event{type: :closed, winner: decode_bid(winner)}

  defp encode_config(%Config{} = config) do
    %{
      "title" => config.title,
      "seller" => config.seller,
      "starting_price" => config.starting_price,
      "reserve" => config.reserve,
      "ends_at" => config.ends_at,
      "snipe_window_ms" => config.snipe_window_ms,
      "extension_ms" => config.extension_ms,
      "max_extensions" => config.max_extensions
    }
  end

  defp decode_config(map) do
    %Config{
      title: Map.fetch!(map, "title"),
      seller: Map.fetch!(map, "seller"),
      starting_price: Map.fetch!(map, "starting_price"),
      reserve: Map.fetch!(map, "reserve"),
      ends_at: Map.fetch!(map, "ends_at"),
      snipe_window_ms: Map.fetch!(map, "snipe_window_ms"),
      extension_ms: Map.fetch!(map, "extension_ms"),
      max_extensions: Map.fetch!(map, "max_extensions")
    }
  end

  defp encode_bid(%Bid{} = bid) do
    %{
      "request_id" => bid.request_id,
      "bidder" => bid.bidder,
      "amount" => bid.amount,
      "at" => bid.at
    }
  end

  defp decode_bid(map) do
    %Bid{
      request_id: Map.fetch!(map, "request_id"),
      bidder: Map.fetch!(map, "bidder"),
      amount: Map.fetch!(map, "amount"),
      at: Map.fetch!(map, "at")
    }
  end
end
