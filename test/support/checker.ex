defmodule Gavel.Checker do
  @moduledoc """
  Verifies the README's five guarantees against what actually happened: the
  committed event logs and every reply clients received.

  `check/3` returns a list of violations, empty when the run is clean.
  """

  import Ecto.Query

  alias Gavel.Repo
  alias Gavel.Rules
  alias Gavel.Rules.Bid
  alias Gavel.Store.Codec
  alias Gavel.Store.EventRecord

  @type log :: %{auction_id: binary(), records: [log_record()]}
  @type log_record :: %{seq: integer(), request_id: binary() | nil, event: Rules.Event.t()}
  @type client_reply :: %{auction_id: binary(), request_id: binary(), reply: term()}

  @doc """
  Reads every auction's committed log from the database.
  """
  @spec load_logs() :: [log()]
  def load_logs do
    from(e in EventRecord, order_by: [asc: e.auction_id, asc: e.seq])
    |> Repo.all()
    |> Enum.group_by(& &1.auction_id)
    |> Enum.map(fn {auction_id, rows} ->
      records =
        Enum.map(rows, fn row ->
          %{seq: row.seq, request_id: row.request_id, event: Codec.decode(row.type, row.payload)}
        end)

      %{auction_id: auction_id, records: records}
    end)
  end

  @doc """
  Checks `logs` and `replies` as of `now_ms`, which decides which auctions are due.
  """
  @spec check([log()], [client_reply()], integer()) :: [tuple()]
  def check(logs, replies, now_ms) do
    logged_bids = Map.new(logs, &{&1.auction_id, logged_bids(&1)})

    Enum.flat_map(logs, &check_log(&1, now_ms)) ++
      Enum.flat_map(replies, &check_reply(&1, Map.get(logged_bids, &1.auction_id, %{})))
  end

  defp logged_bids(%{records: records}) do
    for %{event: %{type: :bid_accepted, bid: bid}} <- records, into: %{} do
      {bid.request_id, bid}
    end
  end

  defp check_log(%{auction_id: id, records: records}, now_ms) do
    events = Enum.map(records, & &1.event)

    sequence_violations(id, records) ++
      request_id_violations(id, records) ++
      replay_violations(id, events) ++
      close_violations(id, events, now_ms)
  end

  defp sequence_violations(id, records) do
    seqs = Enum.map(records, & &1.seq)

    if seqs == Enum.to_list(1..length(seqs)//1) do
      []
    else
      [{:sequence_gap, id, seqs}]
    end
  end

  defp request_id_violations(id, records) do
    for {request_id, count} <- Enum.frequencies_by(records, & &1.request_id),
        request_id != nil,
        count > 1 do
      {:duplicate_request_id, id, request_id}
    end
  end

  defp replay_violations(id, events) do
    case Rules.validate_history(events) do
      {:ok, _view} -> []
      {:error, reason} -> [{:invalid_history, id, reason}]
    end
  end

  defp close_violations(id, events, now_ms) do
    case Enum.filter(events, &(&1.type == :closed)) do
      [] ->
        if due?(events, now_ms), do: [{:missing_close, id}], else: []

      [close] ->
        last_violation(id, events) ++ winner_violation(id, events, close)

      closes ->
        [{:multiple_closes, id, length(closes)}]
    end
  end

  defp due?(events, now_ms) do
    case final_ends_at(events) do
      nil -> false
      ends_at -> now_ms >= ends_at
    end
  end

  # Independent of the rules core for the same reason as `expected_winner/1`.
  defp final_ends_at(events) do
    Enum.reduce(events, nil, fn
      %{type: :opened, config: config}, _ends_at -> config.ends_at
      %{type: :extended, ends_at: ends_at}, _ends_at -> ends_at
      _event, ends_at -> ends_at
    end)
  end

  defp last_violation(id, events) do
    if List.last(events).type == :closed, do: [], else: [{:close_not_last, id}]
  end

  defp winner_violation(id, events, %{winner: winner}) do
    case expected_winner(events) do
      ^winner -> []
      expected -> [{:wrong_winner, id, winner, expected}]
    end
  end

  # Deliberately independent of the rules core: replay already compares winners
  # using that code, so this states the README's rule a second way.
  defp expected_winner(events) do
    bids = for %{type: :bid_accepted, bid: bid} <- events, do: bid
    high_bid = Enum.max_by(bids, & &1.amount, fn -> nil end)
    reserve = Enum.find_value(events, &(&1.type == :opened && &1.config.reserve))

    if high_bid && reserve && high_bid.amount < reserve, do: nil, else: high_bid
  end

  defp check_reply(%{auction_id: id, request_id: request_id, reply: reply}, logged_bids) do
    logged = Map.get(logged_bids, request_id)

    case {reply, logged} do
      {{outcome, %Bid{}, _view}, nil} when outcome in [:accepted, :duplicate] ->
        [{:acked_not_in_log, id, request_id}]

      {{outcome, %Bid{} = acked, _view}, logged} when outcome in [:accepted, :duplicate] ->
        if acked == logged, do: [], else: [{:outcome_mismatch, id, request_id, acked, logged}]

      {{:rejected, _reason}, %Bid{}} ->
        [{:retry_lost_outcome, id, request_id, reply}]

      _ambiguous_or_consistent ->
        []
    end
  end
end
