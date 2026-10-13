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
      {Phoenix.PubSub, name: Gavel.PubSub},
      Gavel.Cluster.Membership,
      {Registry, keys: :unique, name: Gavel.Auction.Registry},
      {DynamicSupervisor, strategy: :one_for_one, name: Gavel.Auction.Supervisor},
      Gavel.Cluster.Placement,
      # Start a worker by calling: Gavel.Worker.start_link(arg)
      # {Gavel.Worker, arg},
      # Start to serve requests, typically the last entry
      GavelWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Gavel.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    GavelWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
