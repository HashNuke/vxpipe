defmodule Vxpipe.CallEngine.Speech.Silero.Model do
  @moduledoc false

  @version "silero_v6.2.3"
  @checksum "1a153a22f4509e292a94e67d6f9b85e8deb25b4988682b7e174c65279d8788e3"
  @derive {Inspect, only: []}
  @enforce_keys [:resource, :sample_rate]
  defstruct @enforce_keys

  def version, do: @version

  def load do
    path = Application.app_dir(:vxpipe_call_engine, "priv/speech/#{@version}.onnx")

    with {:ok, bytes} <- File.read(path),
         true <- Base.encode16(:crypto.hash(:sha256, bytes), case: :lower) == @checksum do
      resource = Ortex.load(path, [:cpu], 3, 1)
      sample_rate = Nx.tensor(16_000, type: :s64) |> Nx.backend_transfer(Ortex.Backend)
      {:ok, %__MODULE__{resource: resource, sample_rate: sample_rate}}
    else
      _failure -> {:error, :model_unavailable}
    end
  rescue
    _error -> {:error, :model_unavailable}
  catch
    _kind, _reason -> {:error, :model_unavailable}
  end
end
