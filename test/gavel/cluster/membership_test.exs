defmodule Gavel.Cluster.MembershipTest do
  # DataCase: a membership change makes the running Placement query the database.
  use Gavel.DataCase, async: false

  alias Gavel.Cluster.Membership
  alias Gavel.Cluster.Ring

  setup do
    Phoenix.PubSub.subscribe(Gavel.PubSub, "cluster")
    :ok
  end

  describe "membership" do
    test "tracks pg joins and leaves, updates ring, and broadcasts changes" do
      pid = spawn(fn -> Process.sleep(:infinity) end)
      on_exit(fn -> Process.exit(pid, :kill) end)

      :pg.join(Gavel.Cluster, :ring_members, pid)

      assert_receive {:membership_changed, members}
      assert members == [node()]
      assert Membership.members() == [node()]
      assert Membership.ring() == Ring.new([node()])

      :pg.leave(Gavel.Cluster, :ring_members, pid)

      assert_receive {:membership_changed, members_after_leave}
      assert members_after_leave == [node()]
      assert Membership.members() == [node()]
      assert Membership.ring() == Ring.new([node()])

      _ = :sys.get_state(Gavel.Cluster.Placement)
    end

    test "returns ring_override when set in app env" do
      override_ring = Ring.new([:override@host])
      Application.put_env(:gavel, :ring_override, override_ring)
      on_exit(fn -> Application.delete_env(:gavel, :ring_override) end)

      assert Membership.ring() == override_ring
    end
  end
end

defmodule Gavel.Cluster.MembershipClusterTest do
  use Gavel.ClusterCase

  alias Gavel.Cluster.Membership

  test "runner is not a ring member while peers are" do
    peers = start_cluster(3)
    runner = node()

    for peer <- peers do
      members = :erpc.call(peer, Membership, :members, [])
      refute runner in members

      for p <- peers do
        assert p in members
      end
    end

    runner_members = Membership.members()
    refute runner in runner_members

    for p <- peers do
      assert p in runner_members
    end
  end
end
