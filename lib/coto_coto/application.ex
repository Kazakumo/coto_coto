defmodule CotoCoto.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      CotoCotoWeb.Telemetry,
      CotoCoto.Repo,
      {DNSCluster, query: Application.get_env(:coto_coto, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: CotoCoto.PubSub},
      # Start a worker by calling: CotoCoto.Worker.start_link(arg)
      # {CotoCoto.Worker, arg},
      # Start to serve requests, typically the last entry
      CotoCotoWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: CotoCoto.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    CotoCotoWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
