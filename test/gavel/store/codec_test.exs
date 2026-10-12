defmodule Gavel.Store.CodecTest do
  use ExUnit.Case, async: true

  alias Gavel.Rules.Bid
  alias Gavel.Rules.Config
  alias Gavel.Rules.Event
  alias Gavel.Store.Codec

  describe "encode/1 and decode/2 round trip" do
    test "round trip of :opened event through Jason.encode!/decode! of payload" do
      event = %Event{
        type: :opened,
        config: %Config{
          title: "Antique Clock",
          seller: "alice",
          starting_price: 1_000,
          reserve: 5_000,
          ends_at: 1_700_000_060_000,
          snipe_window_ms: 30_000,
          extension_ms: 15_000,
          max_extensions: 5
        }
      }

      assert {type, payload, request_id} = Codec.encode(event)
      assert type == "opened"
      assert is_nil(request_id)
      assert is_map(payload)

      decoded_payload = payload |> Jason.encode!() |> Jason.decode!()
      assert Codec.decode(type, decoded_payload) == event
    end

    test "round trip of :opened event with nil reserve" do
      event = %Event{
        type: :opened,
        config: %Config{
          title: "Old Book",
          seller: "bob",
          starting_price: 500,
          reserve: nil,
          ends_at: 1_700_000_060_000,
          snipe_window_ms: 30_000,
          extension_ms: 15_000,
          max_extensions: 3
        }
      }

      assert {type, payload, request_id} = Codec.encode(event)
      assert type == "opened"
      assert is_nil(request_id)

      decoded_payload = payload |> Jason.encode!() |> Jason.decode!()
      assert Codec.decode(type, decoded_payload) == event
    end

    test "round trip of :bid_accepted event through Jason.encode!/decode! of payload" do
      event = %Event{
        type: :bid_accepted,
        bid: %Bid{
          request_id: "req-42",
          bidder: "carol",
          amount: 2_500,
          at: 1_700_000_010_000
        }
      }

      assert {type, payload, request_id} = Codec.encode(event)
      assert type == "bid_accepted"
      assert request_id == "req-42"
      assert is_map(payload)

      decoded_payload = payload |> Jason.encode!() |> Jason.decode!()
      assert Codec.decode(type, decoded_payload) == event
    end

    test "round trip of :extended event through Jason.encode!/decode! of payload" do
      event = %Event{
        type: :extended,
        ends_at: 1_700_000_075_000
      }

      assert {type, payload, request_id} = Codec.encode(event)
      assert type == "extended"
      assert is_nil(request_id)
      assert is_map(payload)

      decoded_payload = payload |> Jason.encode!() |> Jason.decode!()
      assert Codec.decode(type, decoded_payload) == event
    end

    test "round trip of :closed event with winner through Jason.encode!/decode! of payload" do
      event = %Event{
        type: :closed,
        winner: %Bid{
          request_id: "req-99",
          bidder: "dave",
          amount: 10_000,
          at: 1_700_000_050_000
        }
      }

      assert {type, payload, request_id} = Codec.encode(event)
      assert type == "closed"
      assert is_nil(request_id)
      assert is_map(payload)

      decoded_payload = payload |> Jason.encode!() |> Jason.decode!()
      assert Codec.decode(type, decoded_payload) == event
    end

    test "round trip of :closed event with nil winner through Jason.encode!/decode! of payload" do
      event = %Event{
        type: :closed,
        winner: nil
      }

      assert {type, payload, request_id} = Codec.encode(event)
      assert type == "closed"
      assert is_nil(request_id)
      assert is_map(payload)

      decoded_payload = payload |> Jason.encode!() |> Jason.decode!()
      assert Codec.decode(type, decoded_payload) == event
    end
  end
end
