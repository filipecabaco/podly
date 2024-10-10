import "phoenix_html";

import { Socket } from "phoenix";
import { LiveSocket } from "phoenix_live_view";
import topbar from "../vendor/topbar";
import WebRtcVideo from "./web_rtc_video";
let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

const config = {
  longPollFallbackMs: 10000,
  params: { _csrf_token: csrfToken },
  hooks: { WebRtcVideo },
};

let liveSocket = new LiveSocket("/live", Socket, config);

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" });
window.addEventListener("phx:page-loading-start", (_info) => topbar.show(300));
window.addEventListener("phx:page-loading-stop", (_info) => topbar.hide());

liveSocket.connect();
window.liveSocket = liveSocket;
