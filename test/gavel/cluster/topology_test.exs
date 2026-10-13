defmodule Gavel.Cluster.TopologyTest do
  use ExUnit.Case, async: true

  alias Gavel.Cluster.Topology

  describe "from_env/1" do
    test "returns empty list for nil" do
      assert Topology.from_env(nil) == []
    end

    test "returns empty list for empty string or whitespace" do
      assert Topology.from_env("") == []
      assert Topology.from_env("   ") == []
    end

    test "returns empty list for string with only commas or spaces" do
      assert Topology.from_env(",") == []
      assert Topology.from_env(" , , ") == []
    end

    test "configures epmd topology with atom hosts when valid string provided" do
      assert Topology.from_env("gavel@node1,gavel@node2,gavel@node3") == [
               gavel: [
                 strategy: Cluster.Strategy.Epmd,
                 config: [
                   hosts: [:gavel@node1, :gavel@node2, :gavel@node3]
                 ]
               ]
             ]
    end

    test "trims whitespace around node names" do
      assert Topology.from_env(" gavel@node1 ,  gavel@node2 ") == [
               gavel: [
                 strategy: Cluster.Strategy.Epmd,
                 config: [
                   hosts: [:gavel@node1, :gavel@node2]
                 ]
               ]
             ]
    end

    test "configures single node host" do
      assert Topology.from_env("gavel@node1") == [
               gavel: [
                 strategy: Cluster.Strategy.Epmd,
                 config: [
                   hosts: [:gavel@node1]
                 ]
               ]
             ]
    end

    test "Cluster.Supervisor starts with configured topologies" do
      topologies = Topology.from_env("gavel@node1,gavel@node2")
      name = :"test_cluster_sup_#{System.unique_integer([:positive])}"

      {:ok, pid} =
        start_supervised({Cluster.Supervisor, [topologies, [name: name]]})

      assert is_pid(pid)
      assert Process.alive?(pid)
      assert Process.whereis(name) == pid
    end

    test "Gavel.ClusterSupervisor is not started when topologies are not configured" do
      assert Process.whereis(Gavel.ClusterSupervisor) == nil
    end

    test "runtime config configures libcluster topologies when GAVEL_CLUSTER_NODES is set" do
      prev = System.get_env("GAVEL_CLUSTER_NODES")

      try do
        System.put_env("GAVEL_CLUSTER_NODES", "gavel@node1,gavel@node2,gavel@node3")
        runtime_config = Config.Reader.read!("config/runtime.exs", env: :test)

        assert runtime_config[:libcluster][:topologies] == [
                 gavel: [
                   strategy: Cluster.Strategy.Epmd,
                   config: [
                     hosts: [:gavel@node1, :gavel@node2, :gavel@node3]
                   ]
                 ]
               ]
      after
        if prev do
          System.put_env("GAVEL_CLUSTER_NODES", prev)
        else
          System.delete_env("GAVEL_CLUSTER_NODES")
        end
      end
    end
  end
end
