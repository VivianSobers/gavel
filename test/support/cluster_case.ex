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
  Starts N connected peer nodes running :gavel, and takes the runner out of the
  ring. `env` overrides the :gavel app env the peers copy from the runner.
  """
  def start_cluster(n \\ 3, env \\ []) do
    ensure_distribution!()

    Application.put_env(:gavel, :ring_member, false)
    Membership.leave_ring()

    # Registered before any peer starts, so it runs after every peer has stopped.
    on_exit(&restore_runner/0)

    peer_nodes = for _ <- 1..n, do: start_peer(env)

    for n1 <- peer_nodes, n2 <- peer_nodes, n1 != n2 do
      :erpc.call(n1, Node, :connect, [n2])
    end

    await_members(peer_nodes)

    peer_nodes
  end

  @doc """
  Starts one more peer, connects it to `peers`, and waits for all to converge.
  """
  def add_peer(peers, env) do
    node = start_peer(env)

    for peer <- peers, do: :erpc.call(node, Node, :connect, [peer])

    await_members([node | peers])

    node
  end

  defp start_peer(env) do
    cookie = Atom.to_charlist(Node.get_cookie())
    peer_name = :"peer_#{System.unique_integer([:positive])}"
    {:ok, pid, node} = :peer.start_link(%{name: peer_name, args: [~c"-setcookie", cookie]})
    Process.register(pid, node)
    on_exit(fn -> stop_peer(pid) end)

    logger_level = Application.get_env(:logger, :level)

    :erpc.call(node, :code, :add_paths, [:code.get_path()])
    :erpc.call(node, Application, :put_env, [:logger, :level, logger_level])
    :erpc.call(node, Application, :ensure_all_started, [:elixir])

    copy_gavel_env(node, env)

    {:ok, _} = :erpc.call(node, Application, :ensure_all_started, [:gavel])

    node
  end

  defp stop_peer(pid) do
    :peer.stop(pid)
  catch
    :exit, _ -> :ok
  end

  defp restore_runner do
    # Open auctions left behind would be adopted by the runner once it rejoins.
    try do
      truncate_tables()
    after
      Membership.join_ring()
      Application.delete_env(:gavel, :ring_member)
    end

    _ = :sys.get_state(Membership)
    _ = :sys.get_state(Gavel.Cluster.Placement)
  end

  @doc """
  Stops a peer started by `start_cluster/1` without letting it shut down its
  applications, so the rest of the cluster sees an abrupt node loss.
  """
  def kill_peer(node) do
    :peer.stop(Process.whereis(node))
  end

  @doc """
  Waits until every peer in `peers` sees exactly `peers` as the ring members.
  """
  def await_members(peers) do
    expected = Enum.sort(peers)

    for peer <- peers do
      eventually(
        fn -> :erpc.call(peer, Membership, :members, []) == expected end,
        5_000,
        "#{inspect(peer)} did not converge on members #{inspect(expected)}"
      )
    end

    :ok
  end

  @doc """
  Polls `fun` until it returns a truthy value, and fails the test on timeout.
  """
  def eventually(fun, timeout_ms \\ 5_000, message \\ "condition not met before the timeout") do
    do_eventually(fun, System.monotonic_time(:millisecond) + timeout_ms, message)
  end

  defp do_eventually(fun, deadline, message) do
    cond do
      fun.() ->
        :ok

      System.monotonic_time(:millisecond) > deadline ->
        flunk(message)

      true ->
        Process.sleep(50)
        do_eventually(fun, deadline, message)
    end
  end

  defp copy_gavel_env(node, overrides) do
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
      # Dropping :clock leaves peers on the system clock: Gavel.Clock.Test is an
      # Agent that only runs on the test runner.
      |> Keyword.drop([:ring_member, :clock])
      |> Keyword.put(Repo, repo_config)
      |> Keyword.put(GavelWeb.Endpoint, endpoint_config)
      |> Keyword.merge(overrides)

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
end
