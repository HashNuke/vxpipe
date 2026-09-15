defmodule Vxpipe.Persistence.TestTenantGoogleStream do
  @moduledoc false
  use GenServer

  def start_link(_options), do: GenServer.start_link(__MODULE__, [])
  def port(server), do: GenServer.call(server, :port)

  def call(request) do
    {observer, port} = Application.fetch_env!(:vxpipe_persistence, :tenant_google_stream)
    send(observer, {:tenant_google_request, request})
    %{request | scheme: :http, host: "127.0.0.1", port: port}
  end

  @impl true
  def init([]) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :http_bin, ip: {127, 0, 0, 1}])

    {:ok, {_address, port}} = :inet.sockname(listener)
    {:ok, %{listener: listener, port: port}}
  end

  @impl true
  def handle_call(:port, _from, state), do: {:reply, state.port, state, {:continue, :accept}}

  @impl true
  def handle_continue(:accept, state) do
    with {:ok, socket} <- :gen_tcp.accept(state.listener, 10_000),
         {:ok, {:http_request, :POST, _uri, _version}} <- :gen_tcp.recv(socket, 0, 5_000),
         {:ok, size} <- headers(socket, 0),
         :ok <- :inet.setopts(socket, packet: :raw),
         {:ok, _body} <- :gen_tcp.recv(socket, size, 5_000) do
      response =
        JSON.encode!(%{
          "candidates" => [
            %{
              "content" => %{"role" => "model", "parts" => [%{"text" => "Hello back."}]},
              "finishReason" => "STOP"
            }
          ],
          "usageMetadata" => %{
            "promptTokenCount" => 12,
            "candidatesTokenCount" => 3,
            "totalTokenCount" => 15
          }
        })

      body = "data: " <> response <> "\n\n"

      :ok =
        :gen_tcp.send(socket, [
          "HTTP/1.1 200 OK\r\nContent-Type: text/event-stream\r\nConnection: close\r\nContent-Length: ",
          Integer.to_string(byte_size(body)),
          "\r\n\r\n",
          body
        ])

      :gen_tcp.close(socket)
    end

    {:noreply, state}
  end

  defp headers(socket, size) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, :http_eoh} ->
        {:ok, size}

      {:ok, {:http_header, _index, :"Content-Length", _raw, value}} ->
        headers(socket, String.to_integer(value))

      {:ok, {:http_header, _index, _name, _raw, _value}} ->
        headers(socket, size)

      _invalid ->
        {:error, :invalid_request}
    end
  end
end
