defmodule Vxpipe.Console.OperatorLoginTaskTest do
  use ExUnit.Case, async: false

  alias Vxpipe.Console.Endpoint

  setup do
    previous_shell = Mix.shell()
    previous_calls = Application.get_env(:vxpipe_calls, Vxpipe.Calls)
    previous_endpoint = Application.fetch_env!(:vxpipe_console, Endpoint)
    previous_operator_secret = Application.get_env(:vxpipe_console, :operator_login_secret)

    previous_development_secret =
      Application.get_env(:vxpipe_console, :development_operator_login_secret)

    Mix.shell(Mix.Shell.Process)

    Application.put_env(:vxpipe_calls, Vxpipe.Calls,
      operator_login_challenge_repository:
        {Vxpipe.Console.Test.OperatorLoginChallengeRepository, self()}
    )

    Application.put_env(
      :vxpipe_console,
      Endpoint,
      Keyword.merge(previous_endpoint,
        url: [scheme: "http", host: "127.0.0.1", port: 4000],
        secret_key_base: String.duplicate("task-test-secret-", 4)
      )
    )

    Application.put_env(
      :vxpipe_console,
      :operator_login_secret,
      String.duplicate("task-test-secret-", 4)
    )

    on_exit(fn ->
      Mix.shell(previous_shell)
      restore(:vxpipe_calls, Vxpipe.Calls, previous_calls)
      Application.put_env(:vxpipe_console, Endpoint, previous_endpoint)
      restore(:vxpipe_console, :operator_login_secret, previous_operator_secret)

      restore(
        :vxpipe_console,
        :development_operator_login_secret,
        previous_development_secret
      )

      Mix.Task.reenable("vxpipe.login")
    end)

    :ok
  end

  test "prints one token URL and the eight-digit code separately" do
    Mix.Tasks.Vxpipe.Login.run([])

    assert_receive {:mix_shell, :info, ["Operator login URL: " <> url]}
    assert_receive {:mix_shell, :info, ["Operator login code: " <> code]}
    assert Regex.match?(~r/\A[0-9]{8}\z/, code)

    uri = URI.parse(url)
    assert uri.scheme == "http"
    assert uri.host == "127.0.0.1"
    assert uri.port == 4000
    assert ["auth", "login-token", token] = String.split(uri.path, "/", trim: true)
    assert is_nil(uri.fragment)
    assert {:ok, token_bytes} = Base.url_decode64(token, padding: false)
    assert byte_size(token_bytes) == 32

    assert_receive {:operator_login_challenge_inserted, stored}
    refute inspect(stored) =~ token
    refute inspect(stored) =~ code
  end

  test "starts the Persistence application before issuing" do
    assert :ok = Application.stop(:vxpipe_persistence)

    refute Enum.any?(Application.started_applications(), fn {app, _description, _version} ->
             app == :vxpipe_persistence
           end)

    Mix.Tasks.Vxpipe.Login.run([])

    assert Enum.any?(Application.started_applications(), fn {app, _description, _version} ->
             app == :vxpipe_persistence
           end)

    assert_receive {:operator_login_challenge_inserted, _stored}
    assert_receive {:mix_shell, :info, ["Operator login URL: " <> _url]}
    assert_receive {:mix_shell, :info, ["Operator login code: " <> _code]}
  end

  test "rejects an insecure origin before issuing or printing a challenge" do
    update_endpoint(url: [scheme: "http", host: "console.example.com", port: 4000])

    error = assert_raise Mix.Error, fn -> Mix.Tasks.Vxpipe.Login.run([]) end
    assert Exception.message(error) =~ "explicit HTTPS endpoint URL"
    refute_received {:operator_login_challenge_inserted, _challenge}
    refute_received {:mix_shell, :info, _message}
  end

  test "uses the development secret for a loopback login when no explicit secret is set" do
    Application.delete_env(:vxpipe_console, :operator_login_secret)

    Application.put_env(
      :vxpipe_console,
      :development_operator_login_secret,
      String.duplicate("development-only-", 4)
    )

    Mix.Tasks.Vxpipe.Login.run([])

    assert_receive {:operator_login_challenge_inserted, _challenge}
    assert_receive {:mix_shell, :info, ["Operator login URL: http://127.0.0.1:4000/" <> _path]}
    assert_receive {:mix_shell, :info, ["Operator login code: " <> _code]}
  end

  test "does not use the development secret for a non-loopback login" do
    Application.delete_env(:vxpipe_console, :operator_login_secret)

    Application.put_env(
      :vxpipe_console,
      :development_operator_login_secret,
      String.duplicate("development-only-", 4)
    )

    update_endpoint(url: [scheme: "https", host: "console.example.com", port: 443])

    error = assert_raise Mix.Error, fn -> Mix.Tasks.Vxpipe.Login.run([]) end
    assert Exception.message(error) =~ "at least 64 bytes"
    refute_received {:operator_login_challenge_inserted, _challenge}
    refute_received {:mix_shell, :info, _message}
  end

  test "does not use the development secret when a loopback URL listens remotely" do
    Application.delete_env(:vxpipe_console, :operator_login_secret)

    Application.put_env(
      :vxpipe_console,
      :development_operator_login_secret,
      String.duplicate("development-only-", 4)
    )

    update_endpoint(
      url: [scheme: "https", host: "localhost", port: 4000],
      http: false,
      https: [ip: {100, 64, 0, 1}, port: 4000]
    )

    error = assert_raise Mix.Error, fn -> Mix.Tasks.Vxpipe.Login.run([]) end
    assert Exception.message(error) =~ "at least 64 bytes"
    refute_received {:operator_login_challenge_inserted, _challenge}
    refute_received {:mix_shell, :info, _message}
  end

  test "persistence failure prints neither token nor code" do
    Application.put_env(:vxpipe_calls, Vxpipe.Calls,
      operator_login_challenge_repository:
        {Vxpipe.Console.Test.OperatorLoginChallengeRepository, {self(), :unavailable}}
    )

    error = assert_raise Mix.Error, fn -> Mix.Tasks.Vxpipe.Login.run([]) end
    assert Exception.message(error) =~ "check database configuration"
    assert_receive {:operator_login_challenge_inserted, _challenge}
    refute_received {:mix_shell, :info, _message}
  end

  defp update_endpoint(overrides) do
    endpoint = Application.fetch_env!(:vxpipe_console, Endpoint)
    Application.put_env(:vxpipe_console, Endpoint, Keyword.merge(endpoint, overrides))
  end

  defp restore(application, key, nil), do: Application.delete_env(application, key)
  defp restore(application, key, value), do: Application.put_env(application, key, value)
end
