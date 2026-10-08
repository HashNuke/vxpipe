defmodule Vxpipe.Console.AdminCallSpecAuthoringController do
  @moduledoc false
  use Phoenix.Controller, formats: [:json]

  alias Vxpipe.Calls
  alias Vxpipe.Calls.{CallSpecErrors, InstallationOperator}
  alias Vxpipe.Console.CallSpecRevisionJSON

  def show(conn, %{"tenant_key" => tenant, "id" => id} = params) do
    respond(conn, 200, fn ->
      with {:ok, revision} <- revision(Map.get(params, "revision")),
           {:ok, result} <- read(tenant, id, revision) do
        {:ok,
         Map.merge(
           CallSpecRevisionJSON.render(result.call_spec),
           Map.take(result, [:latest_revision, :published_revision])
         )}
      end
    end)
  end

  def create(conn, %{"tenant_key" => tenant}) do
    respond(conn, 201, fn ->
      with {:ok, source} <- source(conn.body_params),
           {:ok, stored} <-
             Calls.save_authorized_call_spec(InstallationOperator.authority(), tenant, source) do
        {:ok, CallSpecRevisionJSON.render(stored)}
      end
    end)
  end

  def update(conn, %{"tenant_key" => tenant, "id" => id}) do
    respond(conn, 201, fn ->
      with {:ok, source} <- source(conn.body_params),
           {:ok, _existing} <- read(tenant, id, nil),
           {:ok, stored} <-
             Calls.save_authorized_call_spec(InstallationOperator.authority(), tenant, source,
               call_spec_id: id
             ) do
        {:ok, CallSpecRevisionJSON.render(stored)}
      end
    end)
  end

  def publish(conn, %{"tenant_key" => tenant, "id" => id, "revision" => input}) do
    respond(conn, 200, fn ->
      with true <- conn.body_params == %{},
           {:ok, revision} when not is_nil(revision) <- revision(input),
           {:ok, _existing} <- read(tenant, id, revision),
           {:ok, stored} <-
             Calls.publish_authorized_call_spec(
               InstallationOperator.authority(),
               tenant,
               id,
               revision
             ) do
        {:ok, CallSpecRevisionJSON.render(stored)}
      else
        false -> {:error, :invalid_request}
        error -> error
      end
    end)
  end

  defp read(tenant, id, revision),
    do:
      Calls.fetch_operator_call_spec(InstallationOperator.authority(), tenant, id,
        revision: revision
      )

  defp source(%{"source" => source} = body) when is_map(source) and map_size(body) == 1,
    do: {:ok, source}

  defp source(_body), do: {:error, :invalid_request}

  defp revision(nil), do: {:ok, nil}

  defp revision(input) when is_binary(input) do
    case Integer.parse(input) do
      {value, ""} when value in 1..2_147_483_647 -> {:ok, value}
      _invalid -> {:error, :invalid_request}
    end
  end

  defp revision(_input), do: {:error, :invalid_request}

  defp respond(conn, status, operation) do
    case safely(operation) do
      {:ok, result} ->
        conn |> put_status(status) |> json(%{call_spec: result})

      {:error, reason} ->
        {status, error} = CallSpecErrors.response(reason)
        conn |> put_status(status) |> json(%{error: error})
    end
  end

  defp safely(operation) do
    operation.()
  rescue
    _error -> {:error, :authoring_unavailable}
  catch
    :exit, _reason -> {:error, :authoring_unavailable}
  end
end
