defmodule Gavel.Cluster.SmokeTest do
  use Gavel.ClusterCase

  test "3 peers see each other in Membership.members/0" do
    peers = start_cluster(3)

    assert length(peers) == 3

    for peer <- peers do
      members = :erpc.call(peer, Gavel.Cluster.Membership, :members, [])

      for p <- peers do
        assert p in members
      end
    end
  end
end
