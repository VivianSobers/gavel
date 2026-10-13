defmodule Gavel.Cluster.MembershipTest do
  # DataCase: a membership change makes the running Placement query the database.
  use Gavel.DataCase, async: false

  alias Gavel.Cluster.Membership
  alias Gavel.Cluster.Ring

  setup do
    Phoenix.PubSub.subscribe(Gavel.PubSub, "cluster")
    initial_members = Membership.members()
    initial_ring = Membership.ring()

    on_exit(fn ->
      if :fake@host in Membership.members() do
        send(Membership, {:nodedown, :fake@host})
      end
    end)

    %{initial_members: initial_members, initial_ring: initial_ring}
  end

  describe "membership" do
    test "tracks nodeup and nodedown, updates ring, and broadcasts changes", %{
      initial_members: initial_members,
      initial_ring: initial_ring
    } do
      fake_node = :fake@host

      refute fake_node in initial_members

      pid = Process.whereis(Membership) || Membership
      send(pid, {:nodeup, fake_node})

      assert_receive {:membership_changed, members_after_up}
      assert fake_node in members_after_up

      current_members = Membership.members()
      assert fake_node in current_members
      assert current_members == members_after_up
      assert current_members == Enum.sort(current_members)

      new_ring = Membership.ring()
      assert new_ring != initial_ring
      assert Ring.new(current_members) == new_ring

      send(pid, {:nodedown, fake_node})

      assert_receive {:membership_changed, members_after_down}
      refute fake_node in members_after_down

      final_members = Membership.members()
      refute fake_node in final_members
      assert final_members == members_after_down
      assert final_members == initial_members

      final_ring = Membership.ring()
      assert final_ring == initial_ring
    end

    test "returns ring_override when set in app env" do
      override_ring = Ring.new([:override@host])
      Application.put_env(:gavel, :ring_override, override_ring)
      on_exit(fn -> Application.delete_env(:gavel, :ring_override) end)

      assert Membership.ring() == override_ring
    end
  end
end
