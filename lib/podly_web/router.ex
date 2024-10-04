defmodule PodlyWeb.Router do
  use PodlyWeb, :router

  pipeline :browser do
    plug(:accepts, ["html"])
    plug(:fetch_session)
    plug(:fetch_live_flash)
    plug(:put_root_layout, html: {PodlyWeb.Layouts, :root})
    plug(:protect_from_forgery)
    plug(:put_secure_browser_headers)
  end

  pipeline :api do
    plug(:accepts, ["json"])
  end

  scope "/", PodlyWeb do
    pipe_through(:browser)

    get("/send/:user", Controllers.UpgradeSocket, :upgrade)
    get("/receive/:user_id/:target_id", Controllers.UpgradeSocket, :upgrade)
    live("/", RoomLive)
  end
end
