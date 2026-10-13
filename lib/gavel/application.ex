defmodule Gavel.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      GavelWeb.Telemetry,
      Gavel.Repo,
      {DNSCluster, query: Application.get_env(:gavel, :dns_cluster_query) || :ignore},
      cluster_supervisor(),
      {Phoenix.PubSub, name: Gavel.PubSub},
      Gavel.Cluster.Membership,
      {Registry, keys: :unique, name: Gavel.Auction.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Gavel.Auction.Supervisor},
      Gavel.Cluster.Placement,
      # Start to serve requests, typically the last entry
      GavelWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Gavel.Supervisor]
    Supervisor.start_link(Enum.reject(children, &is_nil/1), opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GavelWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  # libcluster runs only when runtime.exs configured topologies (GAVEL_CLUSTER_NODES).
  defp cluster_supervisor do
    case Application.get_env(:libcluster, :topologies, []) do
      [] -> nil
      topologies -> {Cluster.Supervisor, [topologies, [name: Gavel.ClusterSupervisor]]}
    end
  end
end
