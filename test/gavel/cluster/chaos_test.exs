defmodule Gavel.Cluster.ChaosTest do
  use Gavel.ClusterCase

  alias Gavel.Auction.Local
  alias Gavel.Checker
  alias Gavel.Clock
  alias Gavel.Cluster.Membership
  alias Gavel.Cluster.Ring
  alias Gavel.Cluster.Rpc
  alias Gavel.Router
  alias Gavel.Rules.Config
  alias Gavel.Store

  @moduletag timeout: 180_000

  @settings %{
    nodes: 5,
    auctions: 20,
    bidders: 12,
    duration_ms: 15_000,
    bid_past_end_ms: 1_500,
    kills: 3,
    kill_interval_ms: 3_000,
    replace_after_ms: 1_500,
    attempts_per_request: 6,
    retry_pause_ms: 100,
    resend_accepted_percent: 15,
    stale_route_percent: 10,
    starting_price: 1_000
  }

  # Production-style reconcile and backoff, unlike the test config.
  @peer_env [placement_interval_ms: 500, router_backoff_ms: [50, 150, 400]]

  defp now_ms, do: Clock.System.now_ms()

  defp seed do
    case System.get_env("CHAOS_SEED") do
      nil -> ExUnit.configuration()[:seed]
      value -> String.to_integer(value)
    end
  end

  defp create_auctions(ends_at) do
    config = %Config{
      title: "Chaos lot",
      seller: "alice",
      starting_price: @settings.starting_price,
      reserve: 3_000,
      ends_at: ends_at,
      snipe_window_ms: 500,
      extension_ms: 1_000,
      max_extensions: 3
    }

    for _ <- 1..@settings.auctions do
      {:ok, id} = Store.create_auction(config)
      id
    end
  end

  defp run_bidder(index, context) do
    :rand.seed(:exsss, {context.seed, index, 0})
    bidder = %{name: "bidder-#{index}", n: 0, minimums: %{}, replies: []}
    bid_until_stopped(bidder, context).replies
  end

  defp bid_until_stopped(bidder, context) do
    if now_ms() >= context.stop_at do
      bidder
    else
      bidder |> place_one_bid(context) |> bid_until_stopped(context)
    end
  end

  defp place_one_bid(bidder, context) do
    id = Enum.random(context.ids)
    request_id = "#{bidder.name}-#{bidder.n}"
    amount = Map.get(bidder.minimums, id, @settings.starting_price) + :rand.uniform(500) - 1
    command = {:place_bid, request_id, bidder.name, amount}

    send_request = fn ->
      send_with_retries(id, request_id, command, context, @settings.attempts_per_request)
    end

    sent = send_request.()
    final_reply = List.last(sent).reply
    resent = if resend?(final_reply), do: send_request.(), else: []

    Process.sleep(:rand.uniform(30))

    %{
      bidder
      | n: bidder.n + 1,
        minimums: update_minimum(bidder.minimums, id, final_reply),
        replies: resent ++ sent ++ bidder.replies
    }
  end

  defp resend?({:accepted, _bid, _view}), do: chance?(@settings.resend_accepted_percent)
  defp resend?(_reply), do: false

  defp chance?(percent), do: :rand.uniform(100) <= percent

  # Returns one entry per attempt, oldest first. An ambiguous reply may mean the
  # bid committed, so it is retried under the same request id.
  defp send_with_retries(id, request_id, command, context, attempts) do
    reply = dispatch_once(id, command, context)
    entry = %{auction_id: id, request_id: request_id, reply: reply}

    if ambiguous?(reply) and attempts > 1 do
      Process.sleep(@settings.retry_pause_ms)
      [entry | send_with_retries(id, request_id, command, context, attempts - 1)]
    else
      [entry]
    end
  end

  defp dispatch_once(id, command, context) do
    entry_node = context.alive |> Agent.get(& &1) |> Enum.random()
    {module, function} = route()

    try do
      Rpc.call(entry_node, module, function, [id, command], 15_000)
    catch
      kind, reason -> {:crash, kind, reason}
    end
  end

  # Rings converge within milliseconds, so without this two servers almost never
  # race for one log and the sequence fence goes unexercised.
  defp route do
    if chance?(@settings.stale_route_percent) do
      {Local, :command}
    else
      {Router, :dispatch}
    end
  end

  defp ambiguous?({:error, _reason}), do: true
  defp ambiguous?({:crash, _kind, _reason}), do: true
  defp ambiguous?(_reply), do: false

  defp update_minimum(minimums, id, {outcome, _bid, view})
       when outcome in [:accepted, :duplicate] do
    Map.put(minimums, id, view.minimum_next_bid)
  end

  defp update_minimum(minimums, id, {:rejected, {:below_minimum, minimum}}) do
    Map.put(minimums, id, minimum)
  end

  defp update_minimum(minimums, _id, _reply), do: minimums

  defp kill_and_replace(alive) do
    Process.sleep(@settings.kill_interval_ms)

    peers = Agent.get(alive, & &1)
    victim = Enum.random(peers)
    survivors = peers -- [victim]

    ring = :erpc.call(victim, Membership, :ring, [])
    orphaned = Enum.count(Store.open_auction_ids(), &(Ring.owner(ring, &1) == victim))

    Agent.update(alive, fn _ -> survivors end)
    kill_peer(victim)
    await_members(survivors)

    Process.sleep(@settings.replace_after_ms)

    replacement = add_peer(survivors, @peer_env)
    Agent.update(alive, &[replacement | &1])

    %{victim: victim, owned_auctions: orphaned}
  end

  defp await_all_closed do
    eventually(fn -> Store.open_auction_ids() == [] end, 30_000)
  rescue
    # Left to the checker, which names exactly which auctions never closed.
    ExUnit.AssertionError -> :timed_out
  end

  defp classify({:accepted, _bid, _view}), do: "accepted"
  defp classify({:duplicate, _bid, _view}), do: "duplicate"
  defp classify({:rejected, {reason, _detail}}), do: "rejected: #{reason}"
  defp classify({:rejected, reason}), do: "rejected: #{reason}"
  defp classify({:error, reason}), do: "error: #{inspect(reason)}"
  defp classify({:crash, _kind, _reason}), do: "crash"

  defp write_report(report) do
    File.mkdir_p!("tmp/chaos")
    path = "tmp/chaos/#{report.seed}-#{now_ms()}.json"
    File.write!(path, Jason.encode!(report, pretty: true))
    path
  end

  test "guarantees hold while nodes die and are replaced under load" do
    seed = seed()
    :rand.seed(:exsss, {seed, 0, 0})

    peers = start_cluster(@settings.nodes, @peer_env)
    {:ok, alive} = Agent.start_link(fn -> peers end)

    ends_at = now_ms() + @settings.duration_ms
    ids = create_auctions(ends_at)
    context = %{seed: seed, ids: ids, alive: alive, stop_at: ends_at + @settings.bid_past_end_ms}

    bidders = for i <- 1..@settings.bidders, do: Task.async(fn -> run_bidder(i, context) end)
    kills = for _ <- 1..@settings.kills, do: kill_and_replace(alive)

    replies = bidders |> Task.await_many(120_000) |> List.flatten()
    closed = await_all_closed()

    violations = Checker.check(Checker.load_logs(), replies, now_ms())
    outcomes = replies |> Enum.map(&classify(&1.reply)) |> Enum.frequencies()
    crashes = for %{reply: {:crash, _, _} = crash} <- replies, do: inspect(crash, limit: 12)

    report = %{
      seed: seed,
      settings: @settings,
      peer_env: Map.new(@peer_env),
      kills: kills,
      all_closed: closed == :ok,
      outcomes: outcomes,
      crash_samples: crashes |> Enum.uniq() |> Enum.take(5),
      violations: Enum.map(violations, &inspect/1)
    }

    IO.puts("\nchaos report: #{write_report(report)}\n#{inspect(Map.delete(report, :settings))}")

    assert violations == []
    assert crashes == []
    assert Map.get(outcomes, "accepted", 0) > 0
    assert Enum.sum(Enum.map(kills, & &1.owned_auctions)) > 0
  end
end
