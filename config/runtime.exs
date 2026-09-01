import Config

if config_env() == :prod do
  port =
    case Integer.parse(System.get_env("PORT", "4000")) do
      {port, ""} when port in 1..65_535 -> port
      _invalid -> raise "PORT must be an integer between 1 and 65535"
    end

  config :vxpipe_server, :http,
    ip: {0, 0, 0, 0},
    port: port,
    startup_log: :info
end
