defmodule Podly.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    File.mkdir("./recordings")

    children = [
      PodlyWeb.Telemetry,
      {Phoenix.PubSub, name: Podly.PubSub},
      PodlyWeb.Endpoint,
      Podly.Room,
      Podly.Recorder
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Podly.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PodlyWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
