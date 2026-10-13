defmodule Gavel.ClusterCase do
  @moduledoc """
  This module defines the setup and helper functions for clustered peer tests.

  Cluster tests do not use the Ecto SQL sandbox because peers cannot share
  a sandbox connection. Database tables (`events` and `auctions`) are truncated
  in setup.
  """

  use ExUnit.CaseTemplate

  alias Ecto.Adapters.SQL
  alias Ecto.Adapters.SQL.Sandbox
  alias Gavel.Cluster.Membership
  alias Gavel.Repo

  using do
    quote do
      @moduletag :cluster
      import Gavel.ClusterCase
    end
  end

  setup do
    if Repo.config()[:pool] == Sandbox do
      Sandbox.mode(Repo, :auto)
    end

    truncate_tables()

    on_exit(fn ->
      if Repo.config()[:pool] == Sandbox do
        Sandbox.mode(Repo, :manual)
      end
    end)

    :ok
  end

  @doc """
  Truncates `events` and `auctions` tables.
  """
  def truncate_tables do
    SQL.query!(Repo, "TRUNCATE TABLE events, auctions CASCADE")
  end

  @doc """
  Starts N peer nodes with :peer.start_link, adds code paths, copies app env
  for :gavel, starts :gavel on each peer, and connects them.
  """
  def start_cluster(n \\ 3) do
    ensure_distribution!()

    Application.put_env(:gavel, :ring_member, false)
    Membership.leave_ring()

    cookie = Atom.to_charlist(Node.get_cookie())
    code_paths = :code.get_path()

    peers =
      for i <- 1..n do
        peer_name = :"peer_#{i}_#{System.unique_integer([:positive])}"
        {:ok, pid, node} = :peer.start_link(%{name: peer_name, args: [~c"-setcookie", cookie]})
        Process.register(pid, node)

        :erpc.call(node, :code, :add_paths, [code_paths])
        :erpc.call(node, Application, :ensure_all_started, [:elixir])

        copy_gavel_env(node)

        {:ok, _} = :erpc.call(node, Application, :ensure_all_started, [:gavel])

        {pid, node}
      end

    peer_nodes = Enum.map(peers, fn {_pid, node} -> node end)
    pids = Enum.map(peers, fn {pid, _node} -> pid end)

    on_exit(fn ->
      Enum.each(pids, fn pid ->
        try do
          :peer.stop(pid)
        catch
          :exit, _ -> :ok
        end
      end)

      Membership.join_ring()
      Application.delete_env(:gavel, :ring_member)
      _ = :sys.get_state(Membership)
      _ = :sys.get_state(Gavel.Cluster.Placement)
    end)

    # Connect all peers to each other
    for n1 <- peer_nodes, n2 <- peer_nodes, n1 != n2 do
      :erpc.call(n1, Node, :connect, [n2])
    end

    # Wait for membership to converge across all peers
    Enum.each(peer_nodes, fn peer ->
      wait_for_members(peer, peer_nodes)
    end)

    peer_nodes
  end

  defp copy_gavel_env(node) do
    env = Application.get_all_env(:gavel)

    repo_config =
      env
      |> Keyword.get(Repo, [])
      |> Keyword.put(:pool, DBConnection.ConnectionPool)
      |> Keyword.put(:pool_size, 5)

    endpoint_config =
      env
      |> Keyword.get(GavelWeb.Endpoint, [])
      |> Keyword.put(:server, false)

    env =
      env
      |> Keyword.delete(:ring_member)
      |> Keyword.put(Repo, repo_config)
      |> Keyword.put(GavelWeb.Endpoint, endpoint_config)

    Enum.each(env, fn {key, value} ->
      :erpc.call(node, Application, :put_env, [:gavel, key, value, [persistent: true]])
    end)
  end

  defp ensure_distribution! do
    unless Node.alive?() do
      System.cmd("epmd", ["-daemon"])
      {:ok, _} = Node.start(:gavel_test, :shortnames)
      Node.set_cookie(:gavel_test)
    end
  end

  defp wait_for_members(peer, expected_nodes, timeout_ms \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    do_wait_for_members(peer, expected_nodes, deadline)
  end

  defp do_wait_for_members(peer, expected_nodes, deadline) do
    members = :erpc.call(peer, Gavel.Cluster.Membership, :members, [])

    if Enum.all?(expected_nodes, &(&1 in members)) do
      :ok
    else
      if System.monotonic_time(:millisecond) > deadline do
        raise "Timeout waiting for peer #{inspect(peer)} to see #{inspect(expected_nodes)}. Current members: #{inspect(members)}"
      else
        Process.sleep(50)
        do_wait_for_members(peer, expected_nodes, deadline)
      end
    end
  end
end
