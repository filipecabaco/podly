defmodule PodlyWeb.Webrtc.Receiver do
  require Logger

  alias ExWebRTC.ICECandidate
  alias ExWebRTC.Media.IVF
  alias ExWebRTC.Media.Ogg
  alias ExWebRTC.MediaStreamTrack
  alias ExWebRTC.PeerConnection
  alias ExWebRTC.RTP.Depayloader
  alias ExWebRTC.RTP.JitterBuffer
  alias ExWebRTC.RTPCodecParameters
  alias ExWebRTC.SessionDescription

  @behaviour WebSock
  @type t() :: %__MODULE__{
          audio_buffer: JitterBuffer.t() | nil,
          audio_depayloader: Depayloader.t() | nil,
          audio_writer: Ogg.Writer.t() | nil,
          in_audio_track_id: String.t() | nil,
          in_video_track_id: String.t() | nil,
          out_audio_track_id: String.t() | nil,
          out_video_track_id: String.t() | nil,
          peer_connection: PeerConnection.peer_connection(),
          target_id: String.t(),
          type: :send | :receive,
          user_id: String.t(),
          video_depayloader: Depayloader.t() | nil,
          video_buffer: JitterBuffer.t() | nil,
          video_frame_counter: non_neg_integer(),
          video_writer: IVF.Writer.t() | nil,
          peer_connection: PeerConnection.peer_connection()
        }

  defstruct audio_buffer: nil,
            audio_depayloader: nil,
            audio_writer: nil,
            in_audio_track_id: nil,
            in_video_track_id: nil,
            out_audio_track_id: nil,
            out_video_track_id: nil,
            target_id: nil,
            type: nil,
            user_id: nil,
            video_depayloader: nil,
            video_buffer: nil,
            video_frame_counter: 0,
            video_writer: nil,
            peer_connection: nil

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
      type: :receiver
    }

    Podly.Room.add_receiver(state)

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
      type: :sender
    }

    {:ok, state}
  end

  @impl true
  def handle_in({msg, [opcode: :text]}, state), do: msg |> Jason.decode!() |> handle_ws_msg(state)

  @impl true
  def handle_info({:ex_webrtc, _from, msg}, state), do: handle_webrtc_msg(msg, state)

  def handle_info({:EXIT, _pc, reason}, state) do
    %{user_id: user_id, type: type} = state
    Podly.Room.leave(user_id, type)
    Logger.info("Peer connection process exited, reason: #{inspect(reason)}")
    {:stop, {:shutdown, :pc_closed}, state}
  end

  @impl true
  def terminate(reason, %{type: :sender} = state) do
    %{video_buffer: video_buffer, audio_buffer: audio_buffer} = state

    {packets, _timer, _buffer} = JitterBuffer.flush(video_buffer)
    state = store_packets(:video, packets, state)

    {packets, _timer, _buffer} = JitterBuffer.flush(audio_buffer)
    state = store_packets(:audio, packets, state)

    %{video_writer: video_writer, audio_writer: audio_writer} = state
    IVF.Writer.close(video_writer)
    Ogg.Writer.close(audio_writer)

    Logger.info("Sender WebSocket connection was terminated, reason: #{inspect(reason)}")
  end

  def terminate(reason, _state) do
    Logger.info("Sender WebSocket connection was terminated, reason: #{inspect(reason)}")
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

  defp handle_webrtc_msg({:track, %{kind: :video, id: id}}, state) do
    %{user_id: user_id} = state
    <<fourcc::little-32>> = "VP80"

    {:ok, video_writer} = IVF.Writer.open("./recordings/#{user_id}.ivf", fourcc: fourcc, height: 640, width: 480, num_frames: 900, timebase_denum: 15, timebase_num: 1)
    {:ok, video_depayloader} = @video_codecs |> hd() |> Depayloader.new()
    video_buffer = JitterBuffer.new()

    state = %{
      state
      | in_video_track_id: id,
        video_buffer: video_buffer,
        video_depayloader: video_depayloader,
        video_writer: video_writer
    }

    :ok = Podly.Room.add_sender(state)
    {:ok, state}
  end

  defp handle_webrtc_msg({:track, %{kind: :audio, id: id}}, state) do
    %{user_id: user_id} = state
    {:ok, audio_writer} = Ogg.Writer.open("./recordings/#{user_id}.ogg")
    {:ok, audio_depayloader} = @audio_codecs |> hd() |> Depayloader.new()
    audio_buffer = JitterBuffer.new()

    state = %{
      state
      | in_audio_track_id: id,
        audio_buffer: audio_buffer,
        audio_depayloader: audio_depayloader,
        audio_writer: audio_writer
    }

    :ok = Podly.Room.add_sender(state)
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
    PeerConnection.send_rtp(state.peer_connection, state.out_audio_track_id, packet)
    broadcast(:audio, packet, state)
    state = store(:audio, packet, state)
    {:ok, state}
  end

  defp handle_webrtc_msg({:rtp, id, _rid, packet}, %{in_video_track_id: id} = state) do
    PeerConnection.send_rtp(state.peer_connection, state.out_video_track_id, packet)
    broadcast(:video, packet, state)
    state = store(:video, packet, state)
    {:ok, state}
  end

  defp handle_webrtc_msg(_msg, state), do: {:ok, state}

  # Broadcast RTP packets to all registered receivers for this specific user id
  defp broadcast(type, packet, %{user_id: self_user_id}) do
    for {_, %{peer_connection: peer_connection} = receiver} <- Podly.Room.get_receivers(self_user_id), Process.alive?(peer_connection) do
      %{out_audio_track_id: out_audio_track_id, out_video_track_id: out_video_track_id} = receiver

      case type do
        :audio -> PeerConnection.send_rtp(peer_connection, out_audio_track_id, packet)
        :video -> PeerConnection.send_rtp(peer_connection, out_video_track_id, packet)
      end
    end
  end

  defp store(:audio, packet, %{audio_buffer: buffer} = state) do
    {packets, _timer, _buffer} = JitterBuffer.insert(buffer, packet)
    store_packets(:audio, packets, state)
  end

  defp store(:video, packet, %{video_buffer: buffer} = state) do
    {packets, _timer, _buffer} = JitterBuffer.insert(buffer, packet)
    store_packets(:video, packets, state)
  end

  defp store_packets(type, packets, state) do
    updated = Map.from_struct(state)
    updated = for packet <- packets, into: updated, do: store_packet(type, packet, updated)
    struct!(__MODULE__, updated)
  end

  defp store_packet(:audio, packet, %{audio_depayloader: depayloader, audio_writer: writer} = state) do
    {opus_packet, depayloader} = Depayloader.depayload(depayloader, packet)
    {:ok, writer} = Ogg.Writer.write_packet(writer, opus_packet)
    %{state | audio_depayloader: depayloader, audio_writer: writer}
  end

  defp store_packet(:video, packet, %{video_depayloader: depayloader, video_writer: writer} = state) do
    case Depayloader.depayload(depayloader, packet) do
      {nil, depayloader} ->
        %{state | video_depayloader: depayloader}

      {vp8_frame, video_depayloader} ->
        IO.inspect(vp8_frame)
        frame = %IVF.Frame{timestamp: state.frames_cnt, data: vp8_frame}
        {:ok, writer} = IVF.Writer.write_frame(writer, frame)
        %{state | video_depayloader: video_depayloader, video_writer: writer, video_frame_counter: state.video_frame_counter + 1}
    end
  end
end
