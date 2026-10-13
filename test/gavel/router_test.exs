defmodule Gavel.RouterTest do
  use Gavel.DataCase, async: false

  alias Gavel.Clock
  alias Gavel.Cluster.Membership
  alias Gavel.Cluster.Ring
  alias Gavel.Router
  alias Gavel.Rules.Bid
  alias Gavel.Rules.Config
  alias Gavel.Rules.View
  alias Gavel.Store

  defmodule FakeRpc do
    use Agent

    def start_link(replies) when is_list(replies) do
      Agent.start_link(fn -> %{calls: [], replies: replies} end, name: __MODULE__)
    end

    def start_link(reply) do
      start_link([reply])
    end

    def calls do
      Agent.get(__MODULE__, fn state -> Enum.reverse(state.calls) end)
    end

    def call(node, module, fun, args, timeout) do
      Agent.get_and_update(__MODULE__, fn state ->
        call_entry = {node, module, fun, args, timeout}

        case state.replies do
          [action | [_ | _] = rest] when is_function(action, 0) ->
            {action.(), %{state | calls: [call_entry | state.calls], replies: rest}}

          [action] when is_function(action, 0) ->
            {action.(), %{state | calls: [call_entry | state.calls]}}

          [reply | [_ | _] = rest] ->
            {reply, %{state | calls: [call_entry | state.calls], replies: rest}}

          [last] ->
            {last, %{state | calls: [call_entry | state.calls]}}

          [] ->
            {nil, %{state | calls: [call_entry | state.calls]}}
        end
      end)
    end
  end

  setup do
    previous_rpc = Application.get_env(:gavel, :rpc)
    previous_backoff = Application.get_env(:gavel, :router_backoff_ms)

    on_exit(fn ->
      if previous_rpc do
        Application.put_env(:gavel, :rpc, previous_rpc)
      else
        Application.delete_env(:gavel, :rpc)
      end

      if previous_backoff do
        Application.put_env(:gavel, :router_backoff_ms, previous_backoff)
      else
        Application.delete_env(:gavel, :router_backoff_ms)
      end

      for {_, pid, _, _} <- DynamicSupervisor.which_children(Gavel.Auction.Supervisor) do
        DynamicSupervisor.terminate_child(Gavel.Auction.Supervisor, pid)
      end
    end)

    :ok
  end

  describe "owner/1" do
    test "returns owner according to the current ring" do
      auction_id = Ecto.UUID.generate()
      expected_owner = Ring.owner(Membership.ring(), auction_id)
      assert Router.owner(auction_id) == expected_owner
    end
  end

  describe "dispatch/2 with fake rpc" do
    test "records target node, module, function, arguments, timeout and returns canned reply" do
      canned_reply = {:accepted, :fake_event}
      start_supervised!({FakeRpc, canned_reply})
      Application.put_env(:gavel, :rpc, FakeRpc)

      auction_id = Ecto.UUID.generate()
      command = {:place_bid, "req-1", "alice", 1_000}
      expected_owner = Ring.owner(Membership.ring(), auction_id)

      assert Router.dispatch(auction_id, command) == canned_reply

      assert [
               {^expected_owner, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000}
             ] = FakeRpc.calls()
    end

    test "records remote owner when ring resolves to another node" do
      canned_reply = {:ok, :remote_result}
      start_supervised!({FakeRpc, canned_reply})
      Application.put_env(:gavel, :rpc, FakeRpc)

      fake_peer = :peer_node@other_host
      membership_pid = Process.whereis(Membership) || Membership
      send(membership_pid, {:nodeup, fake_peer})

      on_exit(fn ->
        send(membership_pid, {:nodedown, fake_peer})
      end)

      assert eventually(fn -> fake_peer in Membership.members() end)

      auction_id =
        Enum.find_value(1..10_000, fn _ ->
          candidate = Ecto.UUID.generate()
          if Ring.owner(Membership.ring(), candidate) == fake_peer, do: candidate
        end)

      assert auction_id != nil
      command = :view

      assert Router.dispatch(auction_id, command) == canned_reply

      assert [{^fake_peer, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000}] =
               FakeRpc.calls()
    end

    test "retries when owner returns {:error, :stale} and succeeds when accepted" do
      accepted_reply = {:accepted, :fake_event}
      start_supervised!({FakeRpc, [{:error, :stale}, accepted_reply]})
      Application.put_env(:gavel, :rpc, FakeRpc)

      auction_id = Ecto.UUID.generate()
      command = {:place_bid, "req-1", "alice", 1_000}
      expected_owner = Ring.owner(Membership.ring(), auction_id)

      assert Router.dispatch(auction_id, command) == accepted_reply

      assert [
               {^expected_owner, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000},
               {^expected_owner, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000}
             ] = FakeRpc.calls()
    end

    test "retries when owner returns {:error, {:erpc, :noconnection}} and succeeds when accepted" do
      accepted_reply = {:accepted, :fake_event}
      start_supervised!({FakeRpc, [{:error, {:erpc, :noconnection}}, accepted_reply]})
      Application.put_env(:gavel, :rpc, FakeRpc)

      auction_id = Ecto.UUID.generate()
      command = {:place_bid, "req-1", "alice", 1_000}
      expected_owner = Ring.owner(Membership.ring(), auction_id)

      assert Router.dispatch(auction_id, command) == accepted_reply

      assert [
               {^expected_owner, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000},
               {^expected_owner, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000}
             ] = FakeRpc.calls()
    end

    test "retries when owner returns {:error, {:erpc, :timeout}} and succeeds when accepted" do
      accepted_reply = {:accepted, :fake_event}
      start_supervised!({FakeRpc, [{:error, {:erpc, :timeout}}, accepted_reply]})
      Application.put_env(:gavel, :rpc, FakeRpc)

      auction_id = Ecto.UUID.generate()
      command = {:place_bid, "req-1", "alice", 1_000}
      expected_owner = Ring.owner(Membership.ring(), auction_id)

      assert Router.dispatch(auction_id, command) == accepted_reply

      assert [
               {^expected_owner, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000},
               {^expected_owner, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000}
             ] = FakeRpc.calls()
    end

    test "retries routing to new owner after node loss causes {:erpc, :noconnection}" do
      fake_peer = :peer_node@other_host
      membership_pid = Process.whereis(Membership) || Membership
      send(membership_pid, {:nodeup, fake_peer})

      on_exit(fn ->
        send(membership_pid, {:nodedown, fake_peer})
      end)

      assert eventually(fn -> fake_peer in Membership.members() end)

      auction_id =
        Enum.find_value(1..10_000, fn _ ->
          candidate = Ecto.UUID.generate()
          if Ring.owner(Membership.ring(), candidate) == fake_peer, do: candidate
        end)

      canned_accepted = {:accepted, :fake_event}

      first_call = fn ->
        send(membership_pid, {:nodedown, fake_peer})
        eventually(fn -> fake_peer not in Membership.members() end)
        {:error, {:erpc, :noconnection}}
      end

      start_supervised!({FakeRpc, [first_call, canned_accepted]})
      Application.put_env(:gavel, :rpc, FakeRpc)

      command = {:place_bid, "req-1", "alice", 1_000}
      assert Router.dispatch(auction_id, command) == canned_accepted

      calls = FakeRpc.calls()
      assert length(calls) == 2

      assert [
               {^fake_peer, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000},
               {new_owner, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000}
             ] = calls

      assert new_owner == node()
    end

    test "re-reads ring on retry and routes to new owner if ring changes" do
      fake_peer = :peer_node@other_host
      membership_pid = Process.whereis(Membership) || Membership
      send(membership_pid, {:nodeup, fake_peer})

      on_exit(fn ->
        send(membership_pid, {:nodedown, fake_peer})
      end)

      assert eventually(fn -> fake_peer in Membership.members() end)

      auction_id =
        Enum.find_value(1..10_000, fn _ ->
          candidate = Ecto.UUID.generate()
          if Ring.owner(Membership.ring(), candidate) == fake_peer, do: candidate
        end)

      canned_accepted = {:accepted, :fake_event}

      first_call = fn ->
        send(membership_pid, {:nodedown, fake_peer})
        eventually(fn -> fake_peer not in Membership.members() end)
        {:error, :stale}
      end

      start_supervised!({FakeRpc, [first_call, canned_accepted]})
      Application.put_env(:gavel, :rpc, FakeRpc)

      command = {:place_bid, "req-1", "alice", 1_000}
      assert Router.dispatch(auction_id, command) == canned_accepted

      calls = FakeRpc.calls()
      assert length(calls) == 2

      assert [
               {^fake_peer, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000},
               {new_owner, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000}
             ] = calls

      assert new_owner == node()
    end

    test "backs off according to :router_backoff_ms application environment" do
      Application.put_env(:gavel, :router_backoff_ms, [50])
      accepted_reply = {:accepted, :fake_event}
      start_supervised!({FakeRpc, [{:error, :stale}, accepted_reply]})
      Application.put_env(:gavel, :rpc, FakeRpc)

      auction_id = Ecto.UUID.generate()
      command = {:place_bid, "req-1", "alice", 1_000}

      start_time = System.monotonic_time(:millisecond)
      assert Router.dispatch(auction_id, command) == accepted_reply
      elapsed = System.monotonic_time(:millisecond) - start_time

      assert elapsed >= 40
      assert length(FakeRpc.calls()) == 2
    end

    test "gives up after fourth failure and returns {:error, :unavailable} when retries are exhausted" do
      start_supervised!({FakeRpc, [{:error, :stale}, {:error, :stale}, {:error, :stale}]})
      Application.put_env(:gavel, :rpc, FakeRpc)

      auction_id = Ecto.UUID.generate()
      command = {:place_bid, "req-1", "alice", 1_000}
      expected_owner = Ring.owner(Membership.ring(), auction_id)

      assert Router.dispatch(auction_id, command) == {:error, :unavailable}

      assert [
               {^expected_owner, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000},
               {^expected_owner, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000},
               {^expected_owner, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000},
               {^expected_owner, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000}
             ] = FakeRpc.calls()
    end

    test "returns {:error, :unavailable} when node loss or timeout retries are exhausted" do
      start_supervised!(
        {FakeRpc,
         [
           {:error, {:erpc, :noconnection}},
           {:error, {:erpc, :timeout}},
           {:error, {:erpc, :noconnection}}
         ]}
      )

      Application.put_env(:gavel, :rpc, FakeRpc)

      auction_id = Ecto.UUID.generate()
      command = {:place_bid, "req-1", "alice", 1_000}

      assert Router.dispatch(auction_id, command) == {:error, :unavailable}
      assert length(FakeRpc.calls()) == 4
    end

    test "returns {:rejected, :too_late} after one call without retrying" do
      start_supervised!({FakeRpc, {:rejected, :too_late}})
      Application.put_env(:gavel, :rpc, FakeRpc)

      auction_id = Ecto.UUID.generate()
      command = {:place_bid, "req-1", "alice", 1_000}
      expected_owner = Ring.owner(Membership.ring(), auction_id)

      assert Router.dispatch(auction_id, command) == {:rejected, :too_late}

      assert [
               {^expected_owner, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000}
             ] = FakeRpc.calls()
    end

    test "returns accepted reply after one call without retrying" do
      accepted_reply =
        {:accepted, %Bid{request_id: "req-1", bidder: "alice", amount: 1_000}, %View{seq: 2}}

      start_supervised!({FakeRpc, accepted_reply})
      Application.put_env(:gavel, :rpc, FakeRpc)

      auction_id = Ecto.UUID.generate()
      command = {:place_bid, "req-1", "alice", 1_000}
      expected_owner = Ring.owner(Membership.ring(), auction_id)

      assert Router.dispatch(auction_id, command) == accepted_reply

      assert [
               {^expected_owner, Gavel.Auction.Local, :command, [^auction_id, ^command], 5_000}
             ] = FakeRpc.calls()
    end
  end

  describe "single-node integration with real rpc on node()" do
    test "routes command through real rpc to local auction server" do
      Application.delete_env(:gavel, :rpc)

      Clock.Test.set(1_699_000_000_000)

      config = %Config{
        title: "Vintage Watch",
        seller: "alice",
        starting_price: 1_000,
        reserve: nil,
        ends_at: 1_700_000_000_000,
        snipe_window_ms: 60_000,
        extension_ms: 30_000,
        max_extensions: 5
      }

      {:ok, auction_id} = Store.create_auction(config)

      assert Router.owner(auction_id) == node()

      assert {:accepted, %Bid{} = bid, %View{} = view} =
               Router.dispatch(auction_id, {:place_bid, "req-real-1", "bob", 1_000})

      assert bid.request_id == "req-real-1"
      assert bid.bidder == "bob"
      assert bid.amount == 1_000
      assert view.seq == 2

      assert {:view, %View{seq: 2}} = Router.dispatch(auction_id, :view)

      assert {:ok, events} = Store.load(auction_id)
      assert length(events) == 2
    end
  end

  defp eventually(check, attempts \\ 50) do
    cond do
      check.() ->
        true

      attempts == 0 ->
        false

      true ->
        Process.sleep(10)
        eventually(check, attempts - 1)
    end
  end
end
