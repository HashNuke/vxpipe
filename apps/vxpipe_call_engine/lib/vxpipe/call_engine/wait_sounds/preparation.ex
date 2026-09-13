defmodule Vxpipe.CallEngine.WaitSounds.Preparation do
  @moduledoc false

  alias Vxpipe.CallEngine.{Error, ResolvedCallPlan}
  alias Vxpipe.CallEngine.OpeningAudio.Settings
  alias Vxpipe.CallEngine.WaitSounds.Assets

  @spec prepare(ResolvedCallPlan.t(), keyword()) ::
          {:ok, ResolvedCallPlan.t()} | {:error, Error.t()}
  def prepare(%ResolvedCallPlan{} = plan, options) do
    with {:ok, settings} <- settings(options),
         {:ok, assets} <- Assets.prepare(plan.tenant_id, plan.wait_sounds, settings) do
      {:ok, %{plan | wait_sound_assets: assets}}
    end
  end

  defp settings(options) do
    configured =
      Keyword.get_lazy(options, :wait_sound_settings, fn ->
        :vxpipe_call_engine
        |> Application.fetch_env!(Vxpipe.CallEngine.Application)
        |> Keyword.fetch!(:opening_audio)
      end)

    case Settings.new(configured) do
      {:ok, settings} ->
        {:ok, settings}

      {:error, _reason} ->
        {:error, Error.new(:wait_sound_unavailable, "The call audio could not be prepared.")}
    end
  end
end
