defmodule Podly.Recorder do
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def init(_opts) do
    {:ok, %{senders: %{}}}
  end

  def receive_packet(type, packet) do
    IO.inspect({type, packet})
  end
end
