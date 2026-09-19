import { AlertTriangle, Check, LoaderCircle } from "lucide-react";
import { useState } from "react";

import { AdminShell } from "./AdminShell";
import { Button } from "./Button";
import { formatAdminLocalTimestamp } from "./formatAdminTimestamp";
import { formatAdminRelativeTime } from "./formatAdminRelativeTime";
import type {
  OnboardingCredentialSubmit,
  OnboardingPageState,
} from "./onboardingTypes";
import { ServiceCredentialForm } from "./ServiceCredentialForm";
import { ServiceLogo } from "./ServiceLogo";
import type { ServiceProvider } from "./serviceTypes";

const providerOptions: Array<{
  provider: ServiceProvider;
  label: string;
  services: string[];
  description: string;
}> = [
  {
    provider: "deepgram",
    label: "Deepgram",
    services: ["Speech to text", "Text to speech"],
    description: "One API key covers both speech services.",
  },
  {
    provider: "google",
    label: "Google AI Studio",
    services: ["Language model"],
    description: "Use Gemini models through an API key.",
  },
  {
    provider: "zenmux",
    label: "Zenmux",
    services: ["Language model"],
    description: "Use Zenmux as the model provider.",
  },
  {
    provider: "telnyx",
    label: "Telnyx",
    services: ["Telephony"],
    description: "Add calling when you are ready to test phone flows.",
  },
  {
    provider: "twilio",
    label: "Twilio",
    services: ["Telephony"],
    description: "Add calling with an Account SID and Auth Token.",
  },
];

export function OnboardingPage({
  state,
  theme = "dark",
  onInstallSamples,
  onSelectProviders,
  onSubmitCredential,
  onManageServices,
  onRetry,
}: {
  state: OnboardingPageState;
  theme?: "dark" | "light";
  onInstallSamples: () => void;
  onSelectProviders?: (providers: ServiceProvider[]) => void;
  onSubmitCredential?: OnboardingCredentialSubmit;
  onManageServices?: () => void;
  onRetry?: () => void;
}) {
  const [selectedProviders, setSelectedProviders] = useState<ServiceProvider[]>(
    [],
  );
  const tenantReady = state.tenant.status === "ready";
  const providersValid = onManageServices
    ? state.samples.status !== "blocked"
    : state.providers.length > 0 &&
      state.providers.every((provider) => provider.status === "valid");

  return (
    <AdminShell breadcrumbs={[{ label: "Getting started" }]} theme={theme}>
      <main className="mx-auto w-full max-w-[1040px] px-4 py-6 sm:px-6 sm:py-8">
        <header className="mb-6 max-w-[70ch]">
          <h1 className="text-2xl font-bold tracking-[-0.03em]">Set up your first call</h1>
          <p className="mt-2 text-sm leading-6 text-[var(--admin-muted)]">
            Vxpipe creates Demo, checks the services you choose, then can load three sample
            call specs. You can rename the tenant later.
          </p>
        </header>

        <ol
          aria-label="Setup progress"
          className="mb-6 grid border-y border-[var(--admin-line)] sm:grid-cols-3 sm:divide-x sm:divide-[var(--admin-line)]"
        >
          <ProgressStep
            complete={tenantReady}
            label="Demo tenant"
            value={tenantReady ? "Ready" : "Creating"}
          />
          <ProgressStep
            complete={providersValid}
            label="Services"
            value={providersValid ? "Validated" : tenantReady ? "Next" : "Waiting"}
          />
          <ProgressStep
            complete={state.samples.status === "complete"}
            label="Sample call specs"
            value={
              state.samples.status === "complete"
                ? "Loaded"
                : providersValid
                  ? "Optional"
                  : "Waiting"
            }
          />
        </ol>

        <div className="overflow-hidden rounded-sm border border-[var(--admin-line)] bg-[var(--admin-panel)]">
          <TenantSection tenant={state.tenant} onRetry={onRetry} />

          {tenantReady ? (
            <section aria-labelledby="services-heading" className="border-t border-[var(--admin-line)] p-4 sm:p-6">
              <div className="mb-5 max-w-[70ch]">
                <h2 className="text-lg font-bold" id="services-heading">Connect your services</h2>
                <p className="mt-1 text-sm leading-6 text-[var(--admin-muted)]">
                  Choose only what you want to configure now. Credentials are tested with the provider before they are marked validated.
                </p>
              </div>

              {onManageServices ? (
                <div className="mb-5">
                  <Button onClick={onManageServices}>Manage services</Button>
                </div>
              ) : null}
              {state.providers.length === 0 && onSelectProviders ? (
                <ProviderSelection
                  onChange={setSelectedProviders}
                  onContinue={() => onSelectProviders(selectedProviders)}
                  selected={selectedProviders}
                />
              ) : (
                <div className="divide-y divide-[var(--admin-row-line)] border-y border-[var(--admin-line)]">
                  {state.providers.map((provider) => (
                    <ProviderSetup
                      key={provider.provider}
                      onSubmit={onSubmitCredential}
                      managed={Boolean(onManageServices)}
                      provider={provider}
                    />
                  ))}
                </div>
              )}
            </section>
          ) : null}

          {tenantReady ? (
            <SampleSection onInstall={onInstallSamples} samples={state.samples} />
          ) : null}
        </div>
      </main>
    </AdminShell>
  );
}

function ProgressStep({
  complete,
  label,
  value,
}: {
  complete: boolean;
  label: string;
  value: string;
}) {
  return (
    <li className="flex items-center gap-3 px-4 py-3">
      <span
        className={`flex size-6 shrink-0 items-center justify-center rounded-full border ${complete ? "border-[var(--admin-green)] text-[var(--admin-green)]" : "border-[var(--admin-line)] text-[var(--admin-muted)]"}`}
      >
        {complete ? (
          <Check aria-hidden="true" size={14} />
        ) : (
          <span aria-hidden="true" className="size-1.5 rounded-full bg-current" />
        )}
      </span>
      <span className="min-w-0">
        <span className="block font-mono text-xs font-bold uppercase tracking-[0.05em]">{label}</span>
        <span className="block text-xs text-[var(--admin-muted)]">{value}</span>
      </span>
    </li>
  );
}

function TenantSection({
  tenant,
  onRetry,
}: {
  tenant: OnboardingPageState["tenant"];
  onRetry?: () => void;
}) {
  if (tenant.status === "creating") {
    return (
      <section aria-labelledby="tenant-heading" className="p-4 sm:p-6">
        <div className="flex items-start gap-3">
          <LoaderCircle
            aria-hidden="true"
            className="mt-0.5 animate-spin text-[var(--admin-muted)] motion-reduce:animate-none"
            size={20}
          />
          <div>
            <h2 className="text-lg font-bold" id="tenant-heading">Preparing Demo</h2>
            <p className="mt-1 text-sm text-[var(--admin-muted)]">
              Creating the first tenant for this installation…
            </p>
          </div>
        </div>
      </section>
    );
  }

  if (tenant.status === "unavailable") {
    return (
      <section aria-labelledby="tenant-heading" className="p-4 sm:p-6">
        <div className="flex items-start gap-3" role="alert">
          <AlertTriangle aria-hidden="true" className="mt-0.5 text-[var(--admin-red)]" size={20} />
          <div>
            <h2 className="text-lg font-bold" id="tenant-heading">
              Demo tenant could not be prepared
            </h2>
            <p className="mt-1 text-sm text-[var(--admin-muted)]">
              {tenant.message}
            </p>
            {onRetry ? (
              <Button className="mt-4" onClick={onRetry}>
                Retry setup
              </Button>
            ) : null}
          </div>
        </div>
      </section>
    );
  }

  return (
    <section
      aria-labelledby="tenant-heading"
      className="flex flex-wrap items-center justify-between gap-4 p-4 sm:p-6"
    >
      <div>
        <h2 className="text-lg font-bold" id="tenant-heading">
          {tenant.name} tenant is ready
        </h2>
        <p className="mt-1 text-sm text-[var(--admin-muted)]">
          Your demo tenant is ready! You can rename the tenant later.
        </p>
      </div>
      <span className="font-mono text-xs text-[var(--admin-muted)]">{tenant.key}</span>
    </section>
  );
}

function ProviderSelection({
  selected,
  onChange,
  onContinue,
}: {
  selected: ServiceProvider[];
  onChange: (providers: ServiceProvider[]) => void;
  onContinue: () => void;
}) {
  return (
    <div>
      <fieldset className="grid gap-2 sm:grid-cols-2">
        <legend className="sr-only">Services to configure</legend>
        {providerOptions.map((option) => {
          const checked = selected.includes(option.provider);
          return (
            <label
              className="flex cursor-pointer gap-3 rounded-sm border border-[var(--admin-line)] bg-[var(--admin-panel)] p-4 transition-colors hover:bg-[var(--admin-soft)]"
              key={option.provider}
            >
              <input
                aria-label={option.label}
                checked={checked}
                className="mt-2 size-4 accent-[var(--admin-green)]"
                onChange={() =>
                  onChange(
                    checked
                      ? selected.filter((provider) => provider !== option.provider)
                      : [...selected, option.provider],
                  )
                }
                type="checkbox"
              />
              <ServiceLogo name={option.label} provider={option.provider} />
              <span className="min-w-0">
                <span className="block text-sm font-semibold">{option.label}</span>
                <span className="mt-0.5 flex flex-wrap gap-x-2 text-xs text-[var(--admin-muted)]">
                  {option.services.map((service) => (
                    <span key={service}>{service}</span>
                  ))}
                </span>
                <span className="mt-2 block text-sm leading-5 text-[var(--admin-muted)]">
                  {option.description}
                </span>
              </span>
            </label>
          );
        })}
      </fieldset>
      <div className="mt-4 flex justify-end">
        <Button disabled={selected.length === 0} onClick={onContinue}>
          {selected.length === 0
            ? "Choose services"
            : `Continue with ${selected.length} ${selected.length === 1 ? "service" : "services"}`}
        </Button>
      </div>
    </div>
  );
}

function ProviderSetup({
  provider,
  onSubmit,
  managed = false,
}: {
  provider: OnboardingPageState["providers"][number];
  onSubmit?: OnboardingCredentialSubmit;
  managed?: boolean;
}) {
  const validatedAt = provider.lastValidatedAt ?? null;
  return (
    <div className="grid gap-4 py-5 first:pt-0 last:pb-0 sm:grid-cols-[minmax(0,1fr)_minmax(280px,0.8fr)]">
      <div className="flex items-start gap-3">
        <ServiceLogo name={provider.label} provider={provider.provider} />
        <div>
          <h3 className="text-sm font-semibold">{provider.label}</h3>
          {provider.source === "platform" ? (
            <p className="mt-2 text-sm text-[var(--admin-muted)]">
              Inherited from platform
            </p>
          ) : null}
          {managed && provider.status === "invalid" ? (
            <p className="mt-2 text-sm text-[var(--admin-red)]">
              Credentials need attention. Open Manage services to update them.
            </p>
          ) : null}
          <p className="mt-1 flex flex-wrap gap-x-2 text-xs text-[var(--admin-muted)]">
            {provider.services.map((service) => (
              <span key={service}>{service}</span>
            ))}
          </p>
          {provider.status === "valid" && validatedAt ? (
            <p className="mt-2 text-sm text-[var(--admin-green)]" title={formatAdminLocalTimestamp(validatedAt)}>
              Validated {formatAdminRelativeTime(validatedAt)}
            </p>
          ) : null}
          {provider.status === "validating" ? (
            <p className="mt-2 text-sm text-[var(--admin-muted)]">
              Testing credentials with {provider.label}…
            </p>
          ) : null}
          {provider.status === "unavailable" && provider.message ? (
            <p className="mt-2 text-sm text-[var(--admin-red)]" role="alert">
              {provider.message}
            </p>
          ) : null}
        </div>
      </div>
      {!managed &&
      onSubmit &&
      (provider.status === "needs_credentials" ||
        provider.status === "invalid") ? (
        <ServiceCredentialForm
          initialProvider={provider.provider}
          message={provider.status === "invalid" ? provider.message : undefined}
          onCancel={() => undefined}
          onSubmit={onSubmit}
          providerLocked
          showCancel={false}
          status={provider.status === "invalid" ? "error" : "idle"}
          submitLabel="Validate and save"
        />
      ) : null}
    </div>
  );
}

function SampleSection({
  samples,
  onInstall,
}: {
  samples: OnboardingPageState["samples"];
  onInstall: () => void;
}) {
  return (
    <section aria-labelledby="samples-heading" className="border-t border-[var(--admin-line)] p-4 sm:p-6">
      <div className="flex flex-col gap-4 sm:flex-row sm:items-start sm:justify-between">
        <div className="max-w-[65ch]">
          <h2 className="text-lg font-bold" id="samples-heading">Start with sample call specs</h2>
          <p className="mt-1 text-sm leading-6 text-[var(--admin-muted)]">
            Load three versioned examples into Demo. This is optional and never overwrites
            an edited call spec.
          </p>
        </div>
        {samples.status === "ready" || samples.status === "error" ? (
          <Button onClick={onInstall}>Load sample call specs</Button>
        ) : null}
        {samples.status === "loading" ? (
          <Button disabled>Loading samples…</Button>
        ) : null}
      </div>

      {samples.status === "blocked" ? (
        <p className="mt-4 text-sm text-[var(--admin-muted)]">
          Sample calls require validated Deepgram and either Google AI Studio or Zenmux credentials.
        </p>
      ) : null}
      {samples.status === "error" && samples.message ? (
        <p className="mt-4 text-sm text-[var(--admin-red)]" role="alert">
          {samples.message}
        </p>
      ) : null}
      {samples.items.length > 0 ? (
        <ul className="mt-5 divide-y divide-[var(--admin-row-line)] border-y border-[var(--admin-line)]">
          {samples.items.map((sample) => (
            <li className="flex items-center justify-between gap-4 py-3" key={sample.id}>
              <span className="text-sm font-semibold">{sample.name}</span>
              <span
                className={`font-mono text-xs uppercase ${sample.status === "failed" ? "text-[var(--admin-red)]" : sample.status === "installed" ? "text-[var(--admin-green)]" : "text-[var(--admin-muted)]"}`}
              >
                {sample.status}
              </span>
            </li>
          ))}
        </ul>
      ) : null}
    </section>
  );
}
