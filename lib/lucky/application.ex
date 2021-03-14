defmodule Lucky.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  def start(_type, _args) do
    children = [
      # Start the Telemetry supervisor
      LuckyWeb.Telemetry,
      # Start the PubSub system
      {Phoenix.PubSub, name: Lucky.PubSub},
      # Start the Endpoint (http/https)
      LuckyWeb.Endpoint,
      {GameServer, name: Lucky.GameServer},
      Lucky.Presence
      # Start a worker by calling: Lucky.Worker.start_link(arg)
      # {Lucky.Worker, arg}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Lucky.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  def config_change(changed, _new, removed) do
    LuckyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
