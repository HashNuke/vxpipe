defmodule Vxpipe.Providers.MorseCodeApi.Endpoint do
  @moduledoc "Validates the private origin shared by Morse API speech and discovery."

  @enforce_keys [:http, :websocket]
  defstruct @enforce_keys

  @type t :: %__MODULE__{http: String.t(), websocket: String.t()}
  @type error :: :endpoint_not_configured | :invalid_endpoint

  @spec configured() :: {:ok, t()} | {:error, error()}
  def configured do
    settings = Application.get_env(:vxpipe_providers, :morse_code_api, [])
    new(Keyword.get(settings, :base_url), allow_http?: Keyword.get(settings, :allow_http?, false))
  end

  @spec new(term(), keyword()) :: {:ok, t()} | {:error, error()}
  def new(origin, options \\ [])
  def new(nil, _options), do: {:error, :endpoint_not_configured}

  def new(origin, options) when is_binary(origin) and is_list(options) do
    with true <- Keyword.keyword?(options),
         {:ok, options} <- Keyword.validate(options, allow_http?: false),
         allow_http? when is_boolean(allow_http?) <- Keyword.fetch!(options, :allow_http?),
         true <- origin != "" and String.trim(origin) == origin,
         {:ok, uri} <- URI.new(origin),
         true <- uri.scheme == "https" or (uri.scheme == "http" and allow_http?),
         host when is_binary(host) and host != "" <- uri.host,
         false <- Regex.match?(~r/[\s\\\/%?#@]/u, host),
         nil <- uri.userinfo,
         nil <- uri.query,
         nil <- uri.fragment,
         true <- uri.path in [nil, "", "/"],
         port when is_integer(port) and port in 1..65_535 <- uri.port do
      uri = %{uri | host: String.downcase(host), path: nil}
      websocket = %{uri | scheme: if(uri.scheme == "https", do: "wss", else: "ws")}
      {:ok, %__MODULE__{http: URI.to_string(uri), websocket: URI.to_string(websocket)}}
    else
      _invalid -> {:error, :invalid_endpoint}
    end
  rescue
    ArgumentError -> {:error, :invalid_endpoint}
  end

  def new(_origin, _options), do: {:error, :invalid_endpoint}
end
