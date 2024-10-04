const WebRtcVideo = {
  async mounted() {
    const userId = this.el.getAttribute("user-id");
    const type = this.el.getAttribute("type");
    const pcConfig = { iceServers: [{ urls: "stun:stun.l.google.com:19302" }] };
    const target_id = this.el.getAttribute("target-id");
    const videoPlayer = document.getElementById(this.el.id);
    const proto = window.location.protocol === "https:" ? "wss:" : "ws:";
    const url =
      type == "send"
        ? `${proto}//${window.location.host}/${type}/${userId}`
        : `${proto}//${window.location.host}/${type}/${userId}/${target_id}`;

    const ws = new WebSocket(url);

    ws.onopen = (_) => start_connection(ws);
    ws.onclose = (event) =>
      console.log("WebSocket connection was terminated:", event);

    const start_connection = async (ws) => {
      const pc = new RTCPeerConnection(pcConfig);
      pc.ontrack = (event) => (videoPlayer.srcObject = event.streams[0]);

      pc.onicecandidate = (event) => {
        if (event.candidate === null) return;
        ws.send(JSON.stringify({ type: "ice", data: event.candidate }));
      };

      if (type == "send") {
        const localStream = await navigator.mediaDevices.getUserMedia({
          video: {
            width: { ideal: 1280 },
            height: { ideal: 720 },
            frameRate: { ideal: 24 },
          },
          audio: {
            channelCount: 2,
            latency: 0,
            noiseSuppression: false,
            highpassFilter: false,
            autoGainControl: false,
            echoCancellation: false,
            sampleRate: 192000,
            sampleSize: 24,
          },
        });

        pc.addTransceiver(localStream.getVideoTracks()[0], {
          direction: "sendrecv",
          streams: [localStream],
          sendEncodings: [
            { rid: "h", maxBitrate: 1200 * 1024 },
            { rid: "m", scaleResolutionDownBy: 2, maxBitrate: 600 * 1024 },
            { rid: "l", scaleResolutionDownBy: 4, maxBitrate: 300 * 1024 },
          ],
        });

        pc.addTrack(localStream.getAudioTracks()[0]);
      }

      ws.onmessage = async (event) => {
        const { type, data } = JSON.parse(event.data);

        switch (type) {
          case "answer":
            await pc.setRemoteDescription(data);
            break;
          case "ice":
            await pc.addIceCandidate(data);
        }
      };

      const offer =
        type == "send"
          ? await pc.createOffer()
          : await pc.createOffer({
              offerToReceiveAudio: true,
              offerToReceiveVideo: true,
            });
      await pc.setLocalDescription(offer);
      ws.send(JSON.stringify({ type: "offer", data: offer }));
      retryPlay(this.el);
    };
  },
};
async function retryPlay(element, attempts = 5) {
  if (this.el && this.el.play() !== undefined) {
    playPromise
      .then((_) => video.pause())
      .catch((error) => {
        console.error("Auto-play was prevented", error);
        if (attempts > 0) {
          retryPlay(element, attempts - 1);
        }
      });
  }
}
export default WebRtcVideo;
