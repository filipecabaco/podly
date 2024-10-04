defmodule PodlyWeb.Controllers.UpgradeSocket do
  use PodlyWeb, :controller

  def upgrade(%{request_path: <<"/send" <> _>>} = conn, params) do
    params = Map.put(params, "type", :send)
    WebSockAdapter.upgrade(conn, PodlyWeb.Webrtc.Receiver, params, [])
  end

  def upgrade(%{request_path: <<"/receive" <> _>>} = conn, params) do
    params = Map.put(params, "type", :receive)
    WebSockAdapter.upgrade(conn, PodlyWeb.Webrtc.Receiver, params, [])
  end
end
