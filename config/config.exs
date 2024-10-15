import Config

config :podly, PodlyWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PodlyWeb.ErrorHTML, json: PodlyWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Podly.PubSub,
  live_view: [signing_salt: "b9tfiB6+"]

config :esbuild,
  version: "0.17.11",
  podly: [
    args: ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

config :tailwind,
  version: "3.4.3",
  podly: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id],
  level: :info

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
