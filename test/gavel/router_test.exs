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

    def start_link(reply) do
      Agent.start_link(fn -> %{calls: [], reply: reply} end, name: __MODULE__)
    end

    def calls do
      Agent.get(__MODULE__, fn state -> Enum.reverse(state.calls) end)
    end

    def call(node, module, fun, args, timeout) do
      Agent.get_and_update(__MODULE__, fn state ->
        {state.reply, %{state | calls: [{node, module, fun, args, timeout} | state.calls]}}
      end)
    end
  end

  setup do
    previous_rpc = Application.get_env(:gavel, :rpc)

    on_exit(fn ->
      if previous_rpc do
        Application.put_env(:gavel, :rpc, previous_rpc)
      else
        Application.delete_env(:gavel, :rpc)
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
