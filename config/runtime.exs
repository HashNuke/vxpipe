import Config

if config_env() == :dev do
  app_host =
    case System.get_env("APP_HOST") do
      nil -> nil
      value -> value |> String.trim() |> String.trim_trailing(".")
    end

  allowed_origins =
    case app_host do
      host when host in [nil, ""] -> []
      host -> ["https://#{host}:5173"]
    end

  port =
    "PORT"
    |> System.get_env("4000")
    |> String.to_integer()

  config :vxpipe_gateway, Vxpipe.Gateway.Application,
    http: [
      port: port,
      cors: [allowed_origins: allowed_origins]
    ]
end
