defmodule PodlyWeb.Webrtc.Receiver do
  require Logger

  alias ExWebRTC.ICECandidate
  alias ExWebRTC.MediaStreamTrack
  alias ExWebRTC.PeerConnection
  alias ExWebRTC.RTPCodecParameters
  alias ExWebRTC.SessionDescription

  @behaviour WebSock
  @type t() :: %__MODULE__{
          peer_connection: PeerConnection.peer_connection(),
          user_id: String.t(),
          target_id: String.t(),
          in_video_track_id: String.t() | nil,
          in_audio_track_id: String.t() | nil,
          out_video_track_id: String.t() | nil,
          out_audio_track_id: String.t() | nil,
          type: :send | :receive
        }

  defstruct peer_connection: nil,
            user_id: nil,
            target_id: nil,
            in_video_track_id: nil,
            in_audio_track_id: nil,
            out_video_track_id: nil,
            out_audio_track_id: nil,
            type: nil

  @ice_servers [
    %{urls: "stun:stun.l.google.com:19302"}
  ]

  @video_codecs [
    %RTPCodecParameters{
      payload_type: 96,
      mime_type: "video/VP8",
      clock_rate: 90_000
    }
  ]

  @audio_codecs [
    %RTPCodecParameters{
      payload_type: 111,
      mime_type: "audio/opus",
      clock_rate: 48_000,
      channels: 2
    }
  ]
  @opts [
    ice_servers: @ice_servers,
    video_codecs: @video_codecs,
    audio_codecs: @audio_codecs
  ]
  @impl true
  def init(%{"user_id" => user_id, "target_id" => target_id, "type" => :receive}) do
    {:ok, pc} = PeerConnection.start_link(@opts)

    stream_id = MediaStreamTrack.generate_stream_id()
    video_track = MediaStreamTrack.new(:video, [stream_id])
    audio_track = MediaStreamTrack.new(:audio, [stream_id])

    {:ok, _sender} = PeerConnection.add_track(pc, video_track)
    {:ok, _sender} = PeerConnection.add_track(pc, audio_track)

    state = %__MODULE__{
      peer_connection: pc,
      user_id: user_id,
      target_id: target_id,
      in_video_track_id: nil,
      in_audio_track_id: nil,
      out_video_track_id: video_track.id,
      out_audio_track_id: audio_track.id,
      type: :receive
    }

    case :ets.lookup(:podly_receivers, target_id) do
      [{target_id, receivers}] -> :ets.insert(:podly_receivers, {target_id, [state | receivers]})
      [] -> :ets.insert(:podly_receivers, {target_id, [state]})
    end

    {:ok, state}
  end

  def init(%{"user" => user_id, "type" => :send}) do
    {:ok, pc} = PeerConnection.start_link(@opts)

    stream_id = MediaStreamTrack.generate_stream_id()
    video_track = MediaStreamTrack.new(:video, [stream_id])
    audio_track = MediaStreamTrack.new(:audio, [stream_id])

    {:ok, _sender} = PeerConnection.add_track(pc, video_track)
    {:ok, _sender} = PeerConnection.add_track(pc, audio_track)

    state = %__MODULE__{
      peer_connection: pc,
      out_video_track_id: video_track.id,
      out_audio_track_id: audio_track.id,
      in_video_track_id: nil,
      in_audio_track_id: nil,
      user_id: user_id,
      target_id: nil,
      type: :send
    }

    {:ok, state}
  end

  @impl true
  def handle_in({msg, [opcode: :text]}, state), do: msg |> Jason.decode!() |> handle_ws_msg(state)

  @impl true
  def handle_info({:ex_webrtc, _from, msg}, state), do: handle_webrtc_msg(msg, state)

  @impl true
  def handle_info({:EXIT, pc, reason}, %{peer_connection: pc, user_id: user_id} = state) do
    :ets.delete(:podly_receivers, user_id)
    :ets.delete(:podly_senders, user_id)
    Phoenix.PubSub.broadcast(Podly.PubSub, "senders", :removed)

    Logger.info("Peer connection process exited, reason: #{inspect(reason)}")
    {:stop, {:shutdown, :pc_closed}, state}
  end

  @impl true
  def terminate(reason, _state) do
    Logger.info("WebSocket connection was terminated, reason: #{inspect(reason)}")
  end

  defp handle_ws_msg(%{"type" => "offer", "data" => data}, state) do
    offer = SessionDescription.from_json(data)

    :ok = PeerConnection.set_remote_description(state.peer_connection, offer)
    {:ok, answer} = PeerConnection.create_answer(state.peer_connection)
    :ok = PeerConnection.set_local_description(state.peer_connection, answer)

    msg =
      answer
      |> SessionDescription.to_json()
      |> then(&Jason.encode!(%{"type" => "answer", "data" => &1}))

    {:push, {:text, msg}, state}
  end

  defp handle_ws_msg(%{"type" => "ice", "data" => data}, state) do
    candidate = ICECandidate.from_json(data)
    :ok = PeerConnection.add_ice_candidate(state.peer_connection, candidate)
    {:ok, state}
  end

  defp handle_webrtc_msg({:ice_candidate, candidate}, state) do
    candidate_json = ICECandidate.to_json(candidate)
    msg = Jason.encode!(%{"type" => "ice", "data" => candidate_json})
    Logger.info("Sent ICE candidate: #{candidate_json["candidate"]}")
    {:push, {:text, msg}, state}
  end

  defp handle_webrtc_msg({:track, track}, %{user_id: user_id} = state) do
    %MediaStreamTrack{kind: kind, id: id} = track

    state =
      case kind do
        :video -> %{state | in_video_track_id: id}
        :audio -> %{state | in_audio_track_id: id}
      end

    if state.type == :send do
      :ets.insert(:podly_senders, {user_id, state})
      Phoenix.PubSub.broadcast(Podly.PubSub, "senders", :added)
    end

    {:ok, state}
  end

  defp handle_webrtc_msg({:rtcp, packets}, state) do
    for packet <- packets do
      case packet do
        {_track_id, %ExRTCP.Packet.PayloadFeedback.PLI{}} when state.in_video_track_id != nil ->
          Logger.info("Received keyframe request. Sending PLI.")
          :ok = PeerConnection.send_pli(state.peer_connection, state.in_video_track_id, "h")

        _ ->
          # do something with other RTCP packets
          :ok
      end
    end

    {:ok, state}
  end

  defp handle_webrtc_msg({:rtp, id, nil, packet}, %{in_audio_track_id: id} = state) do
    if Enum.reject(packet.extensions, &is_nil(&1.data)) != [] do
      PeerConnection.send_rtp(state.peer_connection, state.out_audio_track_id, packet)
      broadcast(nil, packet, state)
    end

    {:ok, state}
  end

  defp handle_webrtc_msg({:rtp, id, rid, packet}, %{in_video_track_id: id} = state) do
    # rid is the id of the simulcast layer (set in `priv/static/script.js`)
    # change it to "m" or "l" to change the layer
    # when simulcast is disabled, `rid == nil`
    if Enum.reject(packet.extensions, &is_nil(&1.data)) != [] do
      if rid == "h" do
        PeerConnection.send_rtp(state.peer_connection, state.out_video_track_id, packet)
        broadcast(rid, packet, state)
      end
    end

    {:ok, state}
  end

  defp handle_webrtc_msg(_msg, state), do: {:ok, state}

  # Broadcast RTP packets to all registered receivers for this specific user id
  defp broadcast(rid, packet, %{user_id: self_user_id}) do
    if Enum.reject(packet.extensions, &is_nil(&1.data)) != [] do
      for {target_id, streams} <- :ets.tab2list(:podly_receivers),
          %{user_id: user_id} = stream <- streams,
          self_user_id == target_id do
        if Process.alive?(stream.peer_connection) do
          if rid in ["h", "m", "l"] do
            PeerConnection.send_rtp(stream.peer_connection, stream.out_video_track_id, packet)
          else
            PeerConnection.send_rtp(stream.peer_connection, stream.out_audio_track_id, packet)
          end
        else
          [{_, streams}] = :ets.lookup(:podly_receivers, target_id)
          streams = Enum.reject(streams, fn s -> s.user_id == user_id end)
          :ets.insert(:podly_receivers, {target_id, streams})
          :ets.delete(:podly_senders, user_id)
          Phoenix.PubSub.broadcast(Podly.PubSub, "senders", :removed)
        end
      end
    end
  end
end
