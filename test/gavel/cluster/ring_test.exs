defmodule Gavel.Cluster.RingTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Gavel.Cluster.Ring

  @node_pool for i <- 1..10, do: :"node_#{i}@host"

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

    property "ring moves few keys on change" do
      check all(
              n <- integer(3..6),
              shuffled <- shuffle(@node_pool),
              ids <- uniq_list_of(string(:alphanumeric, min_length: 8), length: 2000),
              max_runs: 20
            ) do
        nodes = Enum.take(shuffled, n)
        new_node = Enum.at(shuffled, n)
        ring = Ring.new(nodes)
        ring_with_new = Ring.new([new_node | nodes])

        moved_on_add =
          Enum.filter(ids, fn id ->
            Ring.owner(ring, id) != Ring.owner(ring_with_new, id)
          end)

        assert length(moved_on_add) < 2 * 2000 / (n + 1)
        assert Enum.all?(moved_on_add, fn id -> Ring.owner(ring_with_new, id) == new_node end)

        for victim <- nodes do
          ring_without_victim = Ring.new(List.delete(nodes, victim))

          moved_on_remove =
            Enum.filter(ids, fn id ->
              Ring.owner(ring, id) != Ring.owner(ring_without_victim, id)
            end)

          assert Enum.all?(moved_on_remove, fn id -> Ring.owner(ring, id) == victim end)
        end
      end
    end
  end
end
