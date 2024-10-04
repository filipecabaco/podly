import Config

if System.get_env("PHX_SERVER") do
  config :podly, PodlyWeb.Endpoint, server: true
end

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :podly, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :podly, PodlyWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [ip: {0, 0, 0, 0, 0, 0, 0, 0}, port: port],
    secret_key_base: secret_key_base

  if System.get_env("FLY_IO") do
    config :podly, ice_ip_filter: &ExWebRTC.ICE.FlyIpFilter.ip_filter/1
  end
end
