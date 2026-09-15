defmodule Vxpipe.CallEngine.TestSpeechUpgradeServer do
  @moduledoc false
  use GenServer

  def start_link(options), do: GenServer.start_link(__MODULE__, options)

  @impl true
  def init(options) do
    {:ok, listener} =
      :gen_tcp.listen(0, [:binary, active: false, packet: :http_bin, ip: {127, 0, 0, 1}])

    {:ok, {_address, port}} = :inet.sockname(listener)

    send(
      Keyword.fetch!(options, :owner),
      {:speech_upgrade_endpoint, "ws://127.0.0.1:#{port}/speech"}
    )

    {:ok, {listener, Keyword.get(options, :frames, text: "initial")}, {:continue, :accept}}
  end

  @impl true
  def handle_continue(:accept, {listener, frames}) do
    {:ok, socket} = :gen_tcp.accept(listener, 5_000)
    :ok = :gen_tcp.close(listener)
    {:ok, {:http_request, :GET, _path, _version}} = :gen_tcp.recv(socket, 0, 5_000)
    key = headers(socket, nil)

    accept =
      :crypto.hash(:sha, key <> "258EAFA5-E914-47DA-95CA-C5AB0DC85B11") |> Base.encode64()

    # Send the entire upgrade and first frame together to exercise the handoff from
    # HTTP parsing to WebSocket decoding. A real provider may send Connected immediately.
    :ok =
      :gen_tcp.send(socket, [
        "HTTP/1.1 101 Switching Protocols\r\n",
        "Upgrade: websocket\r\nConnection: Upgrade\r\n",
        "Sec-WebSocket-Accept: ",
        accept,
        "\r\n\r\n",
        Enum.map(frames, &frame/1)
      ])

    {:noreply, socket}
  end

  defp frame({:text, text}), do: [<<0x81, byte_size(text)>>, text]
  defp frame({:binary, data}), do: [<<0x82, byte_size(data)>>, data]

  defp headers(socket, key) do
    case :gen_tcp.recv(socket, 0, 5_000) do
      {:ok, {:http_header, _index, name, _reserved, value}} ->
        next = if String.downcase(to_string(name)) == "sec-websocket-key", do: value, else: key
        headers(socket, next)

      {:ok, :http_eoh} ->
        key
    end
  end
end
