defmodule Podly.Room do
  use GenServer

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def init(_opts) do
    Process.send_after(self(), :check_alive, 200)
    {:ok, %{receivers: %{}, senders: %{}}}
  end

  @doc """
  Adds a sender user to the room
  """
  def add_sender(id, peer_connection, video_in, audio_in, video_out, audio_out) do
    content = %{
      peer_connection: peer_connection,
      video_in: video_in,
      audio_in: audio_in,
      video_out: video_out,
      audio_out: audio_out
    }

    GenServer.cast(__MODULE__, {:join, id, :sender, content})
  end

  def add_receiver(id, peer_connection, video_out, audio_out) do
    content = %{
      peer_connection: peer_connection,
      video_out: video_out,
      audio_out: audio_out
    }

    GenServer.cast(__MODULE__, {:join, id, :receiver, content})
  end

  @doc """
  Removes a user from the room.
  """
  def leave(id, type), do: GenServer.cast(__MODULE__, {:leave, id, type})

  @doc """
  Get data for all receivers.
  """
  def get_receivers(self_id), do: GenServer.call(__MODULE__, {:get_receivers, self_id})

  @doc """
  Get data for all senders.
  """
  def get_senders(self_id), do: GenServer.call(__MODULE__, {:get_senders, self_id})

  def handle_cast({:join, id, :sender, content}, %{senders: senders} = state) do
    if Map.has_key?(senders, id) do
      {:noreply, state}
    else
      Phoenix.PubSub.broadcast(Podly.PubSub, "streams", {:joined, id, content})

      senders =
        Map.update(senders, id, content, fn value ->
          value
          |> Enum.reject(&(elem(&1, 1) == nil))
          |> Map.new()
          |> Map.merge(content)
        end)

      {:noreply, %{state | senders: senders}}
    end
  end

  def handle_cast({:join, id, :receiver, content}, %{receivers: receivers} = state) do
    receivers = Map.put(receivers, id, content)
    {:noreply, %{state | receivers: receivers}}
  end

  def handle_cast({:leave, id, :sender}, %{senders: senders} = state)
      when is_map_key(senders, id) do
    {:noreply, state}
  end

  def handle_cast({:leave, id, :sender}, %{senders: senders} = state) do
    Phoenix.PubSub.broadcast(Podly.PubSub, "streams", {:left, id})
    senders = Map.delete(senders, id)
    {:noreply, %{state | senders: senders}}
  end

  def handle_cast({:leave, id, :receiver}, %{receivers: receivers} = state) do
    receivers = Map.delete(receivers, id)
    {:noreply, %{state | receivers: receivers}}
  end

  def handle_call({:get_receivers, id}, _from, %{receivers: receivers} = state) do
    {:reply, Map.delete(receivers, id), state}
  end

  def handle_call({:get_senders, id}, _from, %{senders: senders} = state) do
    {:reply, Map.delete(senders, id), state}
  end

  def handle_info(:check_alive, state) do
    %{senders: senders, receivers: receivers} = state

    senders =
      senders
      |> Enum.map(fn {id, %{peer_connection: peer_connection} = sender} ->
        if !Process.alive?(peer_connection) do
          Phoenix.PubSub.broadcast(Podly.PubSub, "streams", {:left, id})
          nil
        else
          {id, sender}
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    receivers =
      receivers
      |> Enum.map(fn {id, %{peer_connection: peer_connection} = receivers} ->
        if !Process.alive?(peer_connection), do: nil, else: {id, receivers}
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    Process.send_after(self(), :check_alive, 200)
    {:noreply, %{state | senders: senders, receivers: receivers}}
  end
end
