defmodule Gavel.Cluster.RingTest do
  use ExUnit.Case, async: true

  alias Gavel.Cluster.Ring

  describe "ring" do
    test "same owner regardless of node list order" do
      nodes1 = [:node1@host, :node2@host, :node3@host]
      nodes2 = [:node3@host, :node1@host, :node2@host]

      ring1 = Ring.new(nodes1)
      ring2 = Ring.new(nodes2)

      for id <- ["auction-1", "auction-2", "auction-3", "auction-4", "auction-5"] do
        assert Ring.owner(ring1, id) == Ring.owner(ring2, id)
      end
    end

    test "single node owns everything" do
      ring = Ring.new([:singleton@host])

      for id <- ["auction-1", "auction-2", "auction-xyz", "a1", "b2"] do
        assert Ring.owner(ring, id) == :singleton@host
      end
    end

    test "owner is always a member" do
      nodes = [:node1@host, :node2@host, :node3@host]
      ring = Ring.new(nodes)

      for id <- ["auction-1", "auction-2", "auction-3", "auction-4", "auction-5"] do
        assert Ring.owner(ring, id) in nodes
      end
    end
  end
end
