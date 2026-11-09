defmodule Gavel.CheckerTest do
  use ExUnit.Case, async: true

  alias Gavel.Checker
  alias Gavel.Rules.Bid
  alias Gavel.Rules.Config
  alias Gavel.Rules.Event

  @id "auction-1"
  @ends_at 1_000
  @after_end 2_000

  defp config(attrs) do
    struct!(
      %Config{
        title: "Lot",
        seller: "alice",
        starting_price: 1_000,
        reserve: nil,
        ends_at: @ends_at,
        snipe_window_ms: 60,
        extension_ms: 300,
        max_extensions: 5
      },
      attrs
    )
  end

  defp opened(attrs \\ []), do: %Event{type: :opened, config: config(attrs)}

  defp bid(request_id, bidder, amount, at \\ 100) do
    %Bid{request_id: request_id, bidder: bidder, amount: amount, at: at}
  end

  defp placed(%Bid{} = bid), do: %Event{type: :bid_accepted, bid: bid}

  defp closed(winner), do: %Event{type: :closed, winner: winner}

  defp log(events, seqs \\ nil) do
    seqs = seqs || Enum.to_list(1..length(events))

    records =
      for {event, seq} <- Enum.zip(events, seqs) do
        request_id = if event.type == :bid_accepted, do: event.bid.request_id
        %{seq: seq, request_id: request_id, event: event}
      end

    %{auction_id: @id, records: records}
  end

  defp reply(request_id, reply), do: %{auction_id: @id, request_id: request_id, reply: reply}

  defp clean_events do
    [opened(), placed(bid("r1", "bob", 1_000)), closed(bid("r1", "bob", 1_000))]
  end

  describe "a valid run" do
    test "reports nothing for a closed auction whose replies match its log" do
      bob = bid("r1", "bob", 1_000)

      replies = [
        reply("r1", {:accepted, bob, :view}),
        reply("r1", {:duplicate, bob, :view}),
        reply("r2", {:rejected, {:below_minimum, 1_100}})
      ]

      assert Checker.check([log(clean_events())], replies, @after_end) == []
    end

    test "reports nothing for an open auction before its end time" do
      assert Checker.check([log([opened()])], [], @ends_at - 1) == []
    end

    test "ambiguous replies are allowed whether or not the bid committed" do
      replies = [
        reply("r1", {:error, :unavailable}),
        reply("r9", {:error, {:erpc, :timeout}})
      ]

      assert Checker.check([log(clean_events())], replies, @after_end) == []
    end
  end

  describe "guarantee 1: acknowledged bids are committed" do
    test "reports an accepted reply missing from the log" do
      ghost = bid("r9", "dan", 9_000)
      replies = [reply("r9", {:accepted, ghost, :view})]

      assert {:acked_not_in_log, @id, "r9"} in Checker.check(
               [log(clean_events())],
               replies,
               @after_end
             )
    end

    test "reports a duplicate reply missing from the log" do
      ghost = bid("r9", "dan", 9_000)
      replies = [reply("r9", {:duplicate, ghost, :view})]

      assert {:acked_not_in_log, @id, "r9"} in Checker.check(
               [log(clean_events())],
               replies,
               @after_end
             )
    end

    test "reports an accepted reply for an auction with no log" do
      ghost = bid("r9", "dan", 9_000)
      replies = [reply("r9", {:accepted, ghost, :view})]

      assert Checker.check([], replies, @after_end) == [{:acked_not_in_log, @id, "r9"}]
    end
  end

  describe "guarantee 2: gapless sequence" do
    test "reports a gap" do
      events = [opened(), placed(bid("r1", "bob", 1_000))]

      assert {:sequence_gap, @id, [1, 3]} in Checker.check([log(events, [1, 3])], [], 0)
    end

    test "reports a sequence that does not start at 1" do
      assert {:sequence_gap, @id, [2]} in Checker.check([log([opened()], [2])], [], 0)
    end
  end

  describe "guarantee 3: request ids and retries" do
    test "reports a request id logged twice" do
      events = [opened(), placed(bid("r1", "bob", 1_000)), placed(bid("r1", "carol", 5_000))]

      assert {:duplicate_request_id, @id, "r1"} in Checker.check([log(events)], [], 0)
    end

    test "reports a retry that got a different bid back" do
      wrong = bid("r1", "bob", 7_777)
      replies = [reply("r1", {:duplicate, wrong, :view})]
      logged = bid("r1", "bob", 1_000)

      assert {:outcome_mismatch, @id, "r1", wrong, logged} in Checker.check(
               [log(clean_events())],
               replies,
               @after_end
             )
    end

    test "reports a retry rejected although the bid is in the log" do
      replies = [reply("r1", {:rejected, :already_closed})]

      assert {:retry_lost_outcome, @id, "r1", {:rejected, :already_closed}} in Checker.check(
               [log(clean_events())],
               replies,
               @after_end
             )
    end
  end

  describe "guarantee 4: replay accepts the log" do
    test "reports a bid the rules would reject" do
      events = [opened(), placed(bid("r1", "bob", 1))]

      assert {:invalid_history, @id, {:rejected, 2, {:below_minimum, 1_000}}} in Checker.check(
               [log(events)],
               [],
               0
             )
    end

    test "reports a log with no opened event without crashing" do
      assert {:invalid_history, @id, :missing_opened} in Checker.check(
               [log([placed(bid("r1", "bob", 1_000))])],
               [],
               @after_end
             )
    end
  end

  describe "guarantee 5: one correct close" do
    test "reports a due auction with no close" do
      assert Checker.check([log([opened()])], [], @ends_at) == [{:missing_close, @id}]
    end

    test "uses the extended end time to decide whether a close is due" do
      events = [
        opened(),
        placed(bid("r1", "bob", 1_000, 990)),
        %Event{type: :extended, ends_at: 1_290}
      ]

      assert Checker.check([log(events)], [], 1_289) == []
      assert Checker.check([log(events)], [], 1_290) == [{:missing_close, @id}]
    end

    test "reports more than one close" do
      winner = bid("r1", "bob", 1_000)
      events = [opened(), placed(winner), closed(winner), closed(winner)]

      assert {:multiple_closes, @id, 2} in Checker.check([log(events)], [], @after_end)
    end

    test "reports a close that is not the last event" do
      winner = bid("r1", "bob", 1_000)
      events = [opened(), closed(nil), placed(winner)]

      assert {:close_not_last, @id} in Checker.check([log(events)], [], @after_end)
    end

    test "reports a winner that is not the highest bid" do
      low = bid("r1", "bob", 1_000)
      high = bid("r2", "carol", 5_000)
      events = [opened(), placed(low), placed(high), closed(low)]

      assert {:wrong_winner, @id, low, high} in Checker.check([log(events)], [], @after_end)
    end

    test "reports a winner when the reserve was not met" do
      bob = bid("r1", "bob", 1_000)
      events = [opened(reserve: 5_000), placed(bob), closed(bob)]

      assert {:wrong_winner, @id, bob, nil} in Checker.check([log(events)], [], @after_end)
    end

    test "accepts a winner exactly at the reserve" do
      bob = bid("r1", "bob", 5_000)
      events = [opened(reserve: 5_000), placed(bob), closed(bob)]

      assert Checker.check([log(events)], [], @after_end) == []
    end

    test "accepts no winner below the reserve" do
      events = [opened(reserve: 5_000), placed(bid("r1", "bob", 1_000)), closed(nil)]

      assert Checker.check([log(events)], [], @after_end) == []
    end
  end
end
