import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :podly, PodlyWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "PYSVbgFlf0YZYOhCFOJ4JzuZ00o8sIi5Ej5C6ilvqlkhHli3RljNe7S6liV9m8+r",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true
