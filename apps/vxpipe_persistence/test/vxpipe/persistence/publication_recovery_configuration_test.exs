defmodule Vxpipe.Persistence.PublicationRecoveryConfigurationTest do
  use ExUnit.Case, async: true

  alias Vxpipe.Artifacts.CallDetailsWriter
  alias Vxpipe.Calls.PublicationRecovery

  alias Vxpipe.Persistence.{
    CallDetailsPublicationStore,
    PublicationRecoveryConfiguration,
    Repo
  }

  test "keeps recovery disabled unless an embedding host configures it" do
    assert {:ok, []} = PublicationRecoveryConfiguration.children(enabled: false)
  end

  test "builds the Calls recovery child after injecting the owning repository" do
    writer = {CallDetailsWriter, [document_store_options: [bucket: "details-test"]]}

    assert {:ok, [{PublicationRecovery, options}]} =
             PublicationRecoveryConfiguration.children(
               enabled: true,
               publication_artifact_writer: writer,
               batch_size: 25,
               scan_interval_ms: 12_000
             )

    assert Keyword.fetch!(options, :publication_repository) ==
             {CallDetailsPublicationStore, Repo}

    assert Keyword.fetch!(options, :publication_artifact_writer) == writer
    assert Keyword.fetch!(options, :batch_size) == 25
    assert Keyword.fetch!(options, :scan_interval_ms) == 12_000
    refute Keyword.has_key?(options, :enabled)
  end

  test "rejects enabled recovery without a valid artifact writer" do
    assert {:error, :invalid_publication_recovery_configuration} =
             PublicationRecoveryConfiguration.children(enabled: true)
  end
end
