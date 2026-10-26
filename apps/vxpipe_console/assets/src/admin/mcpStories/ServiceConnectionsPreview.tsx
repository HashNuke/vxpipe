import { StoryNavigationContext } from "../stories/storyNavigation";
import {
  ArrowRight,
  ArrowUpRight,
  CheckCheck,
  CircleAlert,
  CircleCheck,
  LoaderCircle,
} from "lucide-react";
import { useContext, useEffect, useRef, useState, type ReactNode } from "react";
import { StoryPageBreadcrumbs } from "../stories/StoryPageBreadcrumbs";
import { Button } from "../Button";
import { SetupDialog } from "../SetupDialog";
import { ConnectedProviders } from "./ConnectedProviders";
import { StoryProviderDialog } from "./StoryProviderDialog";
import { paginatedFixture } from "./directoryPageFixture";
import { remoteCatalog, expandedRemoteCatalog, catalogWithProviders, matchingMcpConnection, type DirectoryLoadState, type ConnectionLoadState } from "./remoteDirectory";
import { ProviderCredentialsDialog } from "./ProviderCredentialsDialog";
import { ExistingServiceDialog, type ExistingService } from "./ExistingServiceDialog";
import { ServiceDirectory, type DirectoryCategory } from "./ServiceDirectory";
import { integrationCategories, useIntegrationCategoryRoute } from "./integrationCategoryRoute";
import { McpServiceIcon as ProviderIcon } from "./McpServiceIcon";
import {
  setupProviders,
  type SetupConnection,
  type SetupProviderId,
} from "../setupCatalog";
import { AuthenticationFields } from "./AuthenticationFields";
import { ConnectionRecovery } from "./ConnectionRecovery";
import { ManageMcpConnection, McpConnectionHeader } from "./ManageMcpConnection";
import { TextField } from "./FormControls";
import {
  connections as fixtureConnections,
  customServerInfo,
  draftFor,
  draftForConnection,
  initialState,
  presets,
  type Connection,
  type Draft,
  type Phase,
  type Preset,
  type Scenario,
} from "./fixtures";
import { validateDraft } from "./validation";
import "./mcp-services-story.css";

type InventoryActions = {
  query: string;
  onBrowse: () => void;
  onConnect: (provider: SetupProviderId) => void;
};
type ProviderDialogActions = {
  providerId: SetupProviderId;
  editing: boolean;
  onClose: () => void;
  onConnected: () => void;
};
/** Shared Storybook-only connection workflow; never mounted by the live app. */
export function ServiceConnectionsPreview({
  scenario = "services",
  tenant = { key: "demo_mcp_preview", name: "Demo" },
  platform = false,
  readOnly: readOnlyProp = false,
  canManagePlatform = false,
  initialProvider,
  initialCategory,
  showMcpInventory = true,
  embedded = false,
  providerConnections,
  connectionLoadState,
  onRetryConnectionStatus,
  renderInventory,
  renderProviderDialog,
}: {
  scenario?: Scenario;
  tenant?: { key: string; name: string };
  platform?: boolean;
  readOnly?: boolean;
  canManagePlatform?: boolean;
  initialProvider?: SetupProviderId | null;
  initialCategory?: DirectoryCategory;
  showMcpInventory?: boolean;
  embedded?: boolean;
  providerConnections?: SetupConnection[];
  connectionLoadState?: ConnectionLoadState;
  onRetryConnectionStatus?: () => void;
  renderInventory?: (actions: InventoryActions) => ReactNode;
  renderProviderDialog?: (actions: ProviderDialogActions) => ReactNode;
}) {
  const navigation = useContext(StoryNavigationContext);
  const Content = embedded ? "div" : "main";
  const [initial] = useState(() => initialState(scenario));
  const paginated = scenario === "directory-paginated" || scenario.startsWith("directory-page-");
  const catalog = catalogWithProviders(["directory-expanded", "directory-search-versions"].includes(scenario) ? expandedRemoteCatalog : paginated ? paginatedFixture(remoteCatalog) : remoteCatalog, scenario === "directory-search-versions");
  const [directoryState, setDirectoryState] = useState<DirectoryLoadState>(() =>
    scenario === "directory-loading" ? "loading" : scenario === "directory-unavailable" ? "unavailable" : scenario === "directory-stale" ? "stale" : "ready");
  const [connectionState, setConnectionState] = useState<ConnectionLoadState>(() =>
    scenario === "directory-connections-loading" ? "loading" : scenario === "directory-connections-error" ? "unavailable" : "ready");
  useEffect(() => {
    if (directoryState !== "loading") return;
    const timer = window.setTimeout(() => setDirectoryState("ready"), 1200);
    return () => window.clearTimeout(timer);
  }, [directoryState]);
  const integrationsPath = platform ? "/platform/services" : `/t/${encodeURIComponent(tenant.key)}/services`;
  const { category: directoryCategory, navigate: setDirectoryCategory, href: categoryHref, search, setSearch, cursor, setCursor } = useIntegrationCategoryRoute(integrationsPath, platform,
    initialCategory ?? (scenario === "picker" ? "ai" : ["directory-search-versions", "directory-paginated", "directory-page-loading", "directory-page-error", "directory-expanded", "directory-loading", "directory-unavailable", "directory-stale", "directory-connections-loading", "directory-connections-error", "directory-reconnect"].includes(scenario) ? "calendar" : scenario.startsWith("directory-")
      ? (scenario.slice(10) as DirectoryCategory)
      : ["connect-telnyx", "connect-twilio"].includes(scenario)
        ? "telephony"
        : scenario === "already-connected-mcp" ? "calendar"
          : (presets.find((preset) => preset.id === scenario)?.category ?? (scenario.startsWith("connect-") ? "ai" : "connected"))),
  );
  const [phase, setPhase] = useState<Phase>(initial.phase);
  const [draft, setDraft] = useState<Draft>(initial.draft);
  const [selected, setSelected] = useState<string | null>(initial.selected);
  const [connections, setConnections] = useState<Connection[]>(() =>
    scenario === "empty" || renderInventory
      ? []
      : fixtureConnections.map((connection) => ({
          ...connection,
          tools: scenario === "connected-no-tools" && connection.id === "reception" ? [] : connection.tools,
          status:
            ["reconnect", "directory-reconnect"].includes(scenario) && connection.id === "reception"
              ? "reconnect"
              : connection.status,
        })),
  );
  const [providers, setProviders] = useState<SetupConnection[]>([
    { provider: "deepgram", source: "platform", status: "connected" },
    { provider: "telnyx", source: "tenant", status: "connected" },
    ...(scenario === "already-connected-ai" ? [{ provider: "google" as const, source: "tenant" as const, status: "connected" as const }] : []),
  ]);
  const [existingService, setExistingService] = useState<ExistingService | null>(
    scenario === "already-connected-ai" ? { name: "Google AI Studio" }
      : scenario === "already-connected-mcp" ? { name: "Cal.com" } : null,
  );
  const [editingProvider, setEditingProvider] = useState(Boolean(initialProvider));
  const [providerDialog, setProviderDialog] = useState<SetupProviderId | null>(
    initialProvider ?? (scenario.startsWith("connect-")
      ? (scenario.slice(8) as SetupProviderId)
      : null),
  );
  const [error, setError] = useState<string | null>(
    scenario === "connection-error"
      ? "The MCP server could not be reached. Check its URL and try again."
      : null,
  );
  const [notice, setNotice] = useState("");
  const operation = useRef(0);
  const errorMessage = useRef<HTMLDivElement>(null);
  const readOnly = readOnlyProp || scenario === "read-only";
  const current = connections.find((connection) => connection.id === selected);
  const modalOpen = phase !== null || providerDialog !== null || existingService !== null;
  const needsBrowserOAuth = draft.auth !== "none" && (draft.auth !== "custom" || (draft.customAuth === "oauth" && draft.grant === "authorization_code"));
  const installationUrlMissing = scenario === "installation-url-required" && needsBrowserOAuth;
  useEffect(() => {
    if (phase === "form" && error) {
      errorMessage.current?.focus();
      errorMessage.current?.scrollIntoView?.({ block: "nearest" });
    }
  }, [error, phase]);
  useEffect(
    () => () => {
      operation.current += 1;
    },
    [],
  );
  function close() {
    operation.current += 1;
    setPhase(null);
    setProviderDialog(null);
    setExistingService(null);
    setError(null);
  }
  function choose(preset: Preset) {
    const existing = matchingMcpConnection(connections, preset);
    if (existing) {
      manage(existing);
      return;
    }
    setDraft(draftFor(preset));
    setSelected(null);
    setError(null);
    setPhase("form");
  }
  function chooseProvider(providerId: SetupProviderId) {
    const existing = (providerConnections ?? providers).find(connection => connection.provider === providerId);
    if (readOnly || (!platform && existing?.source === "platform" && !canManagePlatform)) return;
    setEditingProvider(Boolean(existing));
    setProviderDialog(providerId);
  }
  function update(patch: Partial<Draft>) {
    setDraft((value) => ({ ...value, ...patch }));
    setError(null);
  }
  function finishConnection() {
    const id = selected ?? `preview-${Date.now()}`;
    const tools =
      current?.tools ??
      (draft.preset.id.includes("calendar")
        ? ["list_calendars", "list_events", "create_event"]
        : draft.preset.id === "calcom"
          ? fixtureConnections[0].tools
          : ["search", "get_record", "create_record"]);
    const resolvedAuth = scenario === "discovery-no-auth" && draft.auth === "auto" ? "none" : draft.auth;
    const record: Connection = {
      id,
      name: draft.preset.id === "custom" ? customServerInfo.title : draft.preset.name,
      endpoint: draft.endpoint.trim(),
      preset: draft.preset,
      auth: resolvedAuth,
      authOptions: { customAuth: draft.customAuth, clientAuth: draft.clientAuth, grant: draft.grant },
      status: "connected",
      tools,
      account:
        resolvedAuth === "none" ? undefined : "Authorized account (preview)",
    };
    setConnections((items) => [
      ...items.filter((item) => item.id !== id),
      record,
    ]);
    setSelected(id);
    setPhase("ready");
    setDraft((value) => ({
      ...value,
      token: "",
      password: "",
      clientSecret: "",
      privateKey: "",
      registrationToken: "",
      headers: [],
      tokenParams: [],
    }));
  }
  async function connect() {
    if (installationUrlMissing) return;
    const invalid = validateDraft(draft);
    if (invalid) {
      setError(invalid);
      errorMessage.current?.focus();
      return;
    }
    const attempt = ++operation.current;
    setError(null);
    setPhase("checking");
    await new Promise((resolve) => setTimeout(resolve, 350));
    if (attempt !== operation.current) return;
    if (scenario === "registration-required" && draft.auth === "auto") {
      setPhase("registration");
      return;
    }
    const browserOAuth =
      draft.auth !== "none" &&
      (draft.auth !== "custom" ||
        (draft.customAuth === "oauth" && draft.grant === "authorization_code"));
    if (browserOAuth && scenario !== "discovery-no-auth") setPhase("authorize");
    else finishConnection();
  }
  function manage(connection: Connection) {
    setSelected(connection.id);
    setDraft(draftForConnection(connection));
    setError(null);
    setPhase("manage");
  }
  function reconnect() {
    if (!current) return;
    setDraft(draftForConnection(current));
    setPhase("authorize");
  }
  const title =
    phase === "manage"
      ? (current?.name ?? "MCP connection")
      : phase === "disconnect"
        ? "Disconnect MCP?"
        : phase === "ready"
          ? "Connection ready"
          : phase === "authorize"
            ? "Authorize connection"
            : phase === "checking"
              ? "Checking connection"
                : phase === "registration" ? "Client registration required"
                : phase === "discovery-error" ? "Connection needs attention"
                : draft.preset.id === "custom"
                ? "Connect other MCP"
                : `Connect ${draft.preset.name}`;

  return (
      <div className="mcp-services-preview">
        <Content
          inert={modalOpen || undefined}
          aria-hidden={modalOpen || undefined}
        >
          <StoryPageBreadcrumbs
            root={navigation ? undefined : { label: platform ? "Settings" : tenant.name }}
            tenant={!platform}
            items={[
              { label: platform ? "Platform Integrations" : "Integrations", href: categoryHref("connected"), onSelect: () => setDirectoryCategory("connected") },
              { label: integrationCategories[directoryCategory] ?? catalog.categories.find(item => item.id === directoryCategory)?.name ?? "MCP integrations" },
            ]}
          />
          <ServiceDirectory
            platform={platform} readOnly={readOnly} canManagePlatform={canManagePlatform}
            search={search} onSearch={setSearch} cursor={cursor} onCursor={setCursor}
            pageSize={paginated ? 3 : 20} previewPageState={scenario === "directory-page-loading" ? "loading" : scenario === "directory-page-error" ? "error" : "ready"}
            catalog={catalog} directoryState={directoryState} connectionState={connectionLoadState ?? connectionState}
            providerConnections={providerConnections ?? providers} mcpConnections={connections}
            onRetryDirectory={() => setDirectoryState("ready")} onRetryConnections={onRetryConnectionStatus ?? (() => setConnectionState("ready"))}
            category={directoryCategory} onCategory={setDirectoryCategory} categoryHref={categoryHref}
            connectedCount={(providerConnections ?? providers).length + (platform ? 0 : connections.length)}
            onSelect={choose} onProvider={chooseProvider}
            renderConnected={query => <div className="connected-integrations">
              {renderInventory ? renderInventory({ query,
                onBrowse: () => setDirectoryCategory("ai"),
                onConnect: chooseProvider,
              }) : <ConnectedProviders connections={providers} query={query} platform={platform} readOnly={readOnly} canManagePlatform={canManagePlatform}
                onManage={chooseProvider} />}
              {!platform && showMcpInventory && <section className="service-directory-group connected-integrations-group" aria-label="MCPs">
                <h2>MCPs</h2>
                <div className="service-directory-list">
                  {connections.filter(connection => `${connection.name} ${connection.preset.name}`.toLowerCase().includes(query)).map(connection =>
                    <article className="service-directory-row" aria-label={connection.name} key={connection.id}>
                      <ProviderIcon preset={connection.preset} />
                      <div className="service-directory-name">
                        <h3>{connection.name} <span className="mcp-hint">({connection.tools.length} tools)</span></h3>
                        <p>{connection.account ?? "No authentication"}</p>
                      </div>
                      <span className={`mcp-connection-status ${connection.status === "reconnect" ? "mcp-status-warning" : ""}`} title={connection.status === "reconnect" ? "Reconnect required" : "Connected"}>
                        {connection.status === "reconnect" ? <><CircleAlert size={14} aria-hidden />Reconnect required</> : <><CheckCheck size={18} aria-hidden /><span className="sr-only">Connected</span></>}
                      </span>
                      <Button aria-label={`${readOnly ? "View" : "Manage"} ${connection.name}`} onClick={() => manage(connection)}>{readOnly ? "View" : "Manage"}</Button>
                    </article>)}
                  {!connections.some(connection => `${connection.name} ${connection.preset.name}`.toLowerCase().includes(query)) &&
                    <p className="connected-integrations-empty">{query ? "No matching MCPs." : "No MCPs connected."}</p>}
                </div>
              </section>}
              {notice && <p className="mcp-notice" role="status"><CircleCheck size={16} aria-hidden />{notice}</p>}
            </div>}
          />
        </Content>
        {existingService && <ExistingServiceDialog
          service={existingService}
          tenantName={tenant.name}
          platform={platform}
          onClose={close}
          onViewServices={() => { close(); setDirectoryCategory("connected"); }}
        />}
        {phase && (
          <SetupDialog title={title} headerContent={phase === "manage" && current ? <McpConnectionHeader connection={current} /> : undefined} initialFocusSelector={phase === "manage" ? '[role="tab"][data-state="active"]' : undefined} onClose={close} anchorTop>
            {(phase === "registration" || phase === "discovery-error") && <ConnectionRecovery
              registration={phase === "registration"} name={draft.name} endpoint={draft.endpoint} onClose={close}
              onRetry={() => void connect()}
              onEdit={() => {
                if (phase === "registration") update({ auth: "custom", customAuth: "oauth", clientAuth: "none" });
                setPhase("form");
              }}
            />}
            {phase === "form" && (
              <form
                className="mcp-dialog-form"
                noValidate
                onSubmit={(event) => {
                  event.preventDefault();
                  void connect();
                }}
              >
                <div className="mcp-dialog-scroll">
                  {draft.preset.id === "custom" && <section className="mcp-form-section">
                    <TextField
                      label="MCP server URL"
                      type="url"
                      value={draft.endpoint}
                      onChange={(event) =>
                        update({ endpoint: event.target.value })
                      }
                      placeholder="https://mcp.example.com/mcp"
                    />
                    <p className="mcp-hint mcp-field-note">
                      Remote MCP over Streamable HTTP. Available only to{" "}
                      {tenant.name}.
                    </p>
                  </section>}
                  <section className="mcp-form-section">
                    {draft.preset.id === "custom" && <h3>Authentication</h3>}
                    {installationUrlMissing && <div className="mcp-warning" role="alert"><CircleAlert size={18} aria-hidden /><p>Set a public HTTPS Installation URL in Settings before connecting with OAuth. Ask your Superadmin to configure it.</p></div>}
                    <AuthenticationFields draft={draft} update={update} />
                  </section>
                  {error && (
                    <div
                      role="alert"
                      className="mcp-error"
                      ref={errorMessage}
                      tabIndex={-1}
                    >
                      <CircleAlert size={17} aria-hidden />
                      <p>{error}</p>
                    </div>
                  )}
                </div>
                <footer className="mcp-dialog-footer">
                  <Button type="button" onClick={close}>
                    Cancel
                  </Button>
                  <Button type="submit" className="mcp-primary" disabled={installationUrlMissing}>
                    Connect
                    <ArrowRight size={15} aria-hidden />
                  </Button>
                </footer>
              </form>
            )}
            {phase === "checking" && (
              <>
                <div className="mcp-dialog-scroll mcp-outcome" role="status">
                  <LoaderCircle size={28} className="mcp-spinner" aria-hidden />
                  <h3>Connecting to {draft.name || "your server"}</h3>
                  <p>Checking authentication and the MCP connection.</p>
                </div>
                <footer className="mcp-dialog-footer">
                  <Button onClick={close}>Cancel</Button>
                </footer>
              </>
            )}
            {phase === "authorize" && (
              <>
                <div className="mcp-dialog-scroll mcp-outcome">
                  <ProviderIcon preset={draft.preset} />
                  <h3>
                    Continue with{" "}
                    {draft.preset.id === "custom"
                      ? "your provider"
                      : draft.preset.name}
                  </h3>
                  <p>
                    Authorize <strong>{draft.name || "this MCP server"}</strong> for agents in{" "}
                    {tenant.name}.
                  </p>
                  <div className="mcp-preview-callout">
                    <p>
                      This preview simulates the provider’s sign-in and return
                      to Vxpipe.
                    </p>
                    <Button className="mcp-primary" onClick={finishConnection}>
                      Simulate authorization
                      <ArrowUpRight size={15} aria-hidden />
                    </Button>
                  </div>
                </div>
                <footer className="mcp-dialog-footer">
                  <Button
                    onClick={() => {
                      setPhase(selected ? "manage" : "form");
                      setError(
                        "Authorization canceled. Your connection details are still here; connect when you’re ready.",
                      );
                    }}
                  >
                    Cancel authorization
                  </Button>
                </footer>
              </>
            )}
            {phase === "ready" && current && (
              <>
                <div className="mcp-dialog-scroll mcp-outcome">
                  <CircleCheck
                    className="mcp-success-icon"
                    size={30}
                    aria-hidden
                  />
                  <h3>{current.name} is connected</h3>
                  <p>
                    {current.tools.length ? `${current.tools.length} tools are available. Choose which ones an agent can use in its call spec.` : "This server currently provides no tools. You can refresh its tools from the connection settings when they become available."}
                  </p>
                  <div className="mcp-tool-preview">
                    {current.tools.map((tool) => (
                      <code key={tool}>{tool}</code>
                    ))}
                  </div>
                </div>
                <footer className="mcp-dialog-footer">
                  <Button
                    className="mcp-primary"
                    onClick={() => {
                      close();
                      setDirectoryCategory("connected");
                      setNotice(`${current.name} connected.`);
                    }}
                  >
                    Done
                  </Button>
                </footer>
              </>
            )}
            {phase === "manage" && current && <ManageMcpConnection
              connection={current} draft={draft} update={update} error={error} readOnly={readOnly}
              onSubmit={() => void connect()} onReconnect={reconnect} onDisconnect={() => setPhase("disconnect")} onClose={close}
            />}
            {phase === "disconnect" && current && (
              <>
                <div className="mcp-dialog-scroll">
                  <p>
                    Disconnect <strong>{current.name}</strong> from{" "}
                    {tenant.name}?
                  </p>
                  <p className="mcp-hint">
                    Agents using this connection will lose access to its tools.
                    Their saved tool selections will remain.
                  </p>
                </div>
                <footer className="mcp-dialog-footer">
                  <Button onClick={() => setPhase("manage")}>Cancel</Button>
                  <Button
                    className="mcp-danger"
                    onClick={() => {
                      setConnections((items) =>
                        items.filter((item) => item.id !== current.id),
                      );
                      close();
                      setNotice(`${current.name} disconnected.`);
                    }}
                  >
                    Disconnect MCP
                  </Button>
                </footer>
              </>
            )}
          </SetupDialog>
        )}
        {providerDialog && !readOnly && (platform || canManagePlatform || !(providerConnections ?? providers).some(item => item.provider === providerDialog && item.source === "platform")) && (renderProviderDialog ? <ProviderDialogSlot
          render={renderProviderDialog}
          providerId={providerDialog}
          editing={editingProvider}
          onClose={close}
          onConnected={() => { close(); setDirectoryCategory("connected"); }}
        /> : editingProvider && !platform && providers.some(item => item.provider === providerDialog && item.source === "platform") ? (
          <StoryProviderDialog state={{ provider: providerDialog, status: "idle" }} connections={providers}
            scope={{ kind: "tenant", tenantKey: tenant.key, tenantName: tenant.name }}
            onClose={close} onSubmit={() => undefined} onOverride={() => setEditingProvider(false)} />
        ) : (
          <ProviderCredentialsDialog
            key={providerDialog}
            providerId={providerDialog}
            tenant={tenant}
            editing={editingProvider}
            onClose={close}
            onConnect={(publicKeyConfigured) => {
              setProviders((items) => [
                ...items.filter((item) => item.provider !== providerDialog),
                {
                  provider: providerDialog,
                  status: "connected",
                  source: platform ? "platform" : "tenant",
                  telephonyPublicKeyConfigured: publicKeyConfigured,
                },
              ]);
              close();
              setDirectoryCategory("connected");
              setNotice(
                `${setupProviders.find((item) => item.id === providerDialog)!.name} connected in this preview.`,
              );
            }}
          />
        ))}
      </div>
  );
}

function ProviderDialogSlot({ render, ...actions }: ProviderDialogActions & {
  render: (actions: ProviderDialogActions) => ReactNode;
}) {
  return render(actions);
}
