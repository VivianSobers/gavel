defmodule Gavel.Cluster.RpcTest do
  use ExUnit.Case, async: true

  alias Gavel.Cluster.Rpc

  describe "call/5" do
    test "executes function on local node and returns result" do
      assert Rpc.call(node(), Kernel, :+, [1, 2], 5_000) == 3
    end

    test "returns {:error, {:erpc, :noconnection}} when node is not connected" do
      assert Rpc.call(:nonexistent@nohost, Kernel, :+, [1, 2], 5_000) ==
               {:error, {:erpc, :noconnection}}
    end

    test "returns {:error, {:erpc, :timeout}} on timeout" do
      assert Rpc.call(node(), Process, :sleep, [200], 50) ==
               {:error, {:erpc, :timeout}}
    end
  end
end
