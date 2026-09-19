import { useEffect, useRef, useState } from "react";
import { Button } from "./Button";
import {
  TelephonyApplicationForm,
  type ApplicationDraft,
} from "./TelephonyApplicationForm";
import {
  parseTelephonyApplications,
  type TelephonyApplication,
  type TelephonyApplicationDirectory,
} from "./telephonyApplicationsApi";
import type { ServiceBinding } from "./serviceBindingsApi";

export function TenantTelephonyApplications({
  tenantKey,
  csrfToken,
  binding,
  credentialsLoaded,
  webhookUrl,
  fetchImpl,
  onSessionExpired,
  onConnectionDetails,
}: {
  tenantKey: string;
  csrfToken: string;
  binding?: ServiceBinding;
  credentialsLoaded: boolean;
  webhookUrl?: string | null;
  fetchImpl: typeof fetch;
  onSessionExpired: () => void;
  onConnectionDetails: () => void;
}) {
  const [directory, setDirectory] =
    useState<TelephonyApplicationDirectory | null>(null);
  const [phase, setPhase] = useState<"loading" | "ready" | "unavailable">(
    "loading",
  );
  const [retry, setRetry] = useState(0);
  const [form, setForm] = useState<{
    application: TelephonyApplication | null;
  } | null>(null);
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");
  const saving = useRef<AbortController | null>(null);
  const trigger = useRef<HTMLElement | null>(null);
  const heading = useRef<HTMLHeadingElement>(null);
  const url = `/admin/api/tenants/${encodeURIComponent(tenantKey)}/telephony-applications`;
  const credentialReady =
    credentialsLoaded &&
    binding?.status === "connected" &&
    binding.telephonyPublicKeyConfigured;

  useEffect(() => {
    const controller = new AbortController();
    setPhase("loading");
    setDirectory(null);
    fetchImpl(url, {
      credentials: "same-origin",
      headers: { accept: "application/json" },
      signal: controller.signal,
    })
      .then(async (response) => {
        if (controller.signal.aborted) return;
        if (response.status === 401) onSessionExpired();
        if (!response.ok) throw new Error("unavailable");
        const next = parseTelephonyApplications(
          await response.json(),
          tenantKey,
        );
        if (!controller.signal.aborted) {
          setDirectory(next);
          setPhase("ready");
        }
      })
      .catch(() => {
        if (!controller.signal.aborted) setPhase("unavailable");
      });
    return () => {
      controller.abort();
      saving.current?.abort();
    };
  }, [url, tenantKey, fetchImpl, onSessionExpired, retry]);

  function closeForm() {
    setForm(null);
    setError("");
    requestAnimationFrame(() => trigger.current?.focus());
  }
  function openForm(application: TelephonyApplication | null) {
    trigger.current = document.activeElement as HTMLElement;
    setForm({ application });
    setError("");
    setNotice("");
  }
  function reload() {
    setNotice("");
    setRetry((value) => value + 1);
  }
  async function save(draft: ApplicationDraft) {
    if (!form || saving.current) return;
    const controller = new AbortController();
    saving.current = controller;
    setPending(true);
    setError("");
    const existing = form.application;
    const body = existing
      ? {
          provider_connection_id: draft.provider_connection_id,
          outbound_number: draft.outbound_number,
        }
      : draft;
    let stored = false;
    try {
      const response = await fetchImpl(
        existing ? `${url}/${encodeURIComponent(existing.id)}` : url,
        {
          method: existing ? "PATCH" : "POST",
          credentials: "same-origin",
          signal: controller.signal,
          headers: {
            accept: "application/json",
            "content-type": "application/json",
            "x-csrf-token": csrfToken,
          },
          body: JSON.stringify(body),
        },
      );
      if (controller.signal.aborted) return;
      if (response.status === 401) {
        onSessionExpired();
        throw new Error("Your session expired. Sign in again.");
      }
      if (!response.ok) {
        if (response.status === 409)
          throw new Error(
            "That service name or application ID is already used. Check the mapping and try again.",
          );
        if (response.status === 404)
          throw new Error(
            "This application could not be found. Cancel and reload phone routing.",
          );
        if (response.status === 422) {
          const problem = await response.json().catch(() => null);
          throw new Error(
            problem?.error?.code === "provider_credential_unavailable"
              ? "The Telnyx connection needs a valid API key and public key. Check connection details before trying again."
              : "Check the service name, application ID and caller number, then try again.",
          );
        }
        throw new Error(
          "Application could not be saved. Check the connection and try again.",
        );
      }
      stored = true;
      closeForm();
      setPhase("loading");
      setDirectory(null);
      const reloaded = await fetchImpl(url, {
        credentials: "same-origin",
        headers: { accept: "application/json" },
        signal: controller.signal,
      });
      if (controller.signal.aborted) return;
      if (reloaded.status === 401) onSessionExpired();
      if (!reloaded.ok) throw new Error("reload unavailable");
      const next = parseTelephonyApplications(await reloaded.json(), tenantKey);
      if (controller.signal.aborted) return;
      setDirectory(next);
      setPhase("ready");
      setNotice("Application saved.");
      requestAnimationFrame(() => heading.current?.focus());
    } catch (problem) {
      if (controller.signal.aborted) return;
      if (stored) {
        setPhase("unavailable");
        setNotice("Application saved. Retry to load its current routing.");
        requestAnimationFrame(() => heading.current?.focus());
      } else
        setError(
          problem instanceof Error
            ? problem.message
            : "Application could not be saved. Try again.",
        );
    } finally {
      if (saving.current === controller) {
        saving.current = null;
        setPending(false);
      }
    }
  }

  const credentialMessage = !credentialsLoaded
    ? "Load service connections to check Telnyx configuration."
    : !binding
      ? "Connect Telnyx with an API key and public key to add an application."
      : binding.status !== "connected"
        ? "The Telnyx connection is unavailable. Check its credentials before configuring applications."
        : !binding.telephonyPublicKeyConfigured
          ? binding.source === "tenant"
            ? "Add a public key to this tenant’s Telnyx connection before configuring applications."
            : "Add a public key to the platform Telnyx connection before configuring applications."
          : `Using ${binding.source === "tenant" ? "this tenant’s" : "platform"} Telnyx credentials.`;
  return (
    <section
      className="phone-applications"
      aria-labelledby="phone-routing-title"
      aria-busy={phase === "loading"}
    >
      <div className="setup-group-heading">
        <div>
          <h2 id="phone-routing-title" ref={heading} tabIndex={-1}>
            Phone routing
          </h2>
          <p>
            Match a Telnyx Voice API application to a service name for this
            tenant.
          </p>
        </div>
        <Button
          disabled={
            !credentialReady || phase !== "ready" || form !== null || pending
          }
          onClick={() => openForm(null)}
        >
          Add application
        </Button>
      </div>
      <div className="phone-connection-summary">
        <p>{credentialMessage}</p>
        <Button
          variant="ghost"
          disabled={!credentialsLoaded || pending}
          onClick={onConnectionDetails}
        >
          Connection details
        </Button>
      </div>
      {phase === "loading" ? (
        <p role="status">Loading phone routing…</p>
      ) : phase === "unavailable" ? (
        <div className="phone-routing-unavailable" role="alert">
          <p>
            {notice ||
              "Phone routing could not be loaded. Your saved applications are safe."}
          </p>
          <Button onClick={reload}>Retry phone routing</Button>
        </div>
      ) : (
        <>
          {directory?.applications.length === 0 && !form ? (
            <p className="phone-routing-empty">
              Add an existing Telnyx application, then publish a call spec that
              receives a number through its service name.
            </p>
          ) : null}
          {form ? (
            <TelephonyApplicationForm
              key={form.application?.id ?? "new"}
              application={form.application}
              pending={pending}
              error={error}
              onSave={(draft) => void save(draft)}
              onCancel={closeForm}
            />
          ) : null}
          <ul className="phone-application-list">
            {directory?.applications.map((application) => (
              <li key={application.id}>
                <div className="phone-application-heading">
                  <h3>{application.name}</h3>
                  <Button
                    variant="ghost"
                    disabled={form !== null || pending || !credentialReady}
                    onClick={() => openForm(application)}
                    aria-label={`Edit ${application.name}`}
                  >
                    Edit
                  </Button>
                </div>
                <dl className="phone-application-metadata">
                  <div>
                    <dt>Voice API application</dt>
                    <dd>{application.provider_connection_id}</dd>
                  </div>
                  {application.outbound_number ? (
                    <div>
                      <dt>Outbound caller</dt>
                      <dd>{application.outbound_number}</dd>
                    </div>
                  ) : null}
                </dl>
                {application.published_routes.length === 0 ? (
                  <p>
                    No published numbers. Publish a call spec with a receiving
                    number for <code>{application.name}</code>.
                  </p>
                ) : (
                  <ul
                    className="phone-published-routes"
                    aria-label={`Published numbers for ${application.name}`}
                  >
                    {application.published_routes.map((route) => (
                      <li
                        key={`${route.call_spec_id}:${route.call_spec_revision}:${route.participant_ref}`}
                      >
                        <span className="phone-route-number">
                          {route.number}
                        </span>
                        <span>
                          {route.call_spec_name} · revision{" "}
                          {route.call_spec_revision} · {route.participant_ref}
                        </span>
                        {route.ambiguous ? (
                          <p className="phone-application-error">
                            Multiple published routes use this number. Publish
                            one route before receiving calls.
                          </p>
                        ) : null}
                      </li>
                    ))}
                  </ul>
                )}
              </li>
            ))}
          </ul>
          {directory?.truncated ? (
            <p role="status">
              Showing the first 100 applications or 500 routes. Additional
              mappings may not be displayed; conflict warnings include them.
            </p>
          ) : null}
          {notice ? <p role="status">{notice}</p> : null}
          <Button
            variant="ghost"
            disabled={form !== null || pending}
            onClick={reload}
          >
            Reload phone routing
          </Button>
        </>
      )}
      <div className="phone-routing-guidance">
        <p>
          In Telnyx, assign each incoming number to its Voice API application
          and use the webhook URL shown in Connection details. Publish number
          routes through the call-spec API.
        </p>
        {!webhookUrl?.startsWith("https:") ? (
          <p>
            Live call events require a publicly reachable HTTPS webhook URL.
          </p>
        ) : null}
        <p>
          A successful live call still needs to be verified after local
          configuration.
        </p>
      </div>
    </section>
  );
}
