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

    {:ok,
     {listener, Keyword.fetch!(options, :owner), Keyword.get(options, :frames, text: "initial")},
     {:continue, :accept}}
  end

  @impl true
  def handle_continue(:accept, {listener, owner, frames}) do
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

    send(owner, {:speech_upgrade_connected, self()})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:send, frames}, socket) do
    :ok = :gen_tcp.send(socket, Enum.map(frames, &frame/1))
    {:noreply, socket}
  end

  @impl true
  def handle_call({:send, frames}, _from, socket) do
    :ok = :gen_tcp.send(socket, Enum.map(frames, &frame/1))
    {:reply, :ok, socket}
  end

  def handle_call(:disconnect, _from, socket) do
    :ok = :gen_tcp.close(socket)
    {:stop, :normal, :ok, socket}
  end

  defp frame({:text, text}), do: frame(0x81, text)
  defp frame({:binary, data}), do: frame(0x82, data)
  defp frame(:close), do: frame(0x88, <<>>)
  defp frame({:close, code, reason}), do: frame(0x88, <<code::16, reason::binary>>)

  defp frame(opcode, payload) when byte_size(payload) <= 125,
    do: [<<opcode, byte_size(payload)>>, payload]

  defp frame(opcode, payload) when byte_size(payload) <= 65_535,
    do: [<<opcode, 126, byte_size(payload)::16>>, payload]

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
