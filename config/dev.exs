import Config

config :podly, PodlyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "aJaYkO8i98ibYKgFlSTtwSOo3SpgVcnKaZ4WBuY8VMI2kOEmRSvW8QSh77J3Ztu+",
  watchers: [
    esbuild: {Esbuild, :install_and_run, [:podly, ~w(--sourcemap=inline --watch)]},
    tailwind: {Tailwind, :install_and_run, [:podly, ~w(--watch)]}
  ]

config :podly, PodlyWeb.Endpoint,
  live_reload: [
    patterns: [
      ~r"priv/static/(?!uploads/).*(js|css|png|jpeg|jpg|gif|svg)$",
      ~r"lib/podly_web/(controllers|live|components)/.*(ex|heex)$"
    ]
  ]

config :podly, dev_routes: true

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20

config :phoenix, :plug_init_mode, :runtime

config :phoenix_live_view,
  debug_heex_annotations: true,
  enable_expensive_runtime_checks: true
