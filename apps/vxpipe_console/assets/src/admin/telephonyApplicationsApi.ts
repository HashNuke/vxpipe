export type PublishedPhoneRoute = {
  number: string;
  call_spec_id: string;
  call_spec_name: string;
  call_spec_revision: number;
  participant_ref: string;
  ambiguous: boolean;
};
export type TelephonyApplication = {
  id: string;
  name: string;
  provider_connection_id: string;
  outbound_number: string | null;
  published_routes: PublishedPhoneRoute[];
};
export type TelephonyApplicationDirectory = {
  applications: TelephonyApplication[];
  truncated: boolean;
};

const record = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);
const text = (value: unknown, maximum = 128): value is string =>
  typeof value === "string" && value.length > 0 && value.length <= maximum;
const phone = (value: unknown): value is string =>
  typeof value === "string" && /^\+[1-9][0-9]{1,14}$/.test(value);
const invalid = () => new Error("Phone routing could not be loaded.");

export function parseTelephonyApplications(
  value: unknown,
  tenant: string,
): TelephonyApplicationDirectory {
  if (
    !record(value) ||
    !record(value.tenant) ||
    value.tenant.key !== tenant ||
    !Array.isArray(value.applications) ||
    value.applications.length > 100 ||
    typeof value.truncated !== "boolean"
  )
    throw invalid();
  const ids = new Set<string>();
  const names = new Set<string>();
  let routeCount = 0;
  const applications = value.applications.map((item): TelephonyApplication => {
    if (
      !record(item) ||
      !text(item.id) ||
      !/^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/.test(
        item.id,
      ) ||
      !text(item.name) ||
      !/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(item.name) ||
      !text(item.provider_connection_id) ||
      !/^[\x21-\x7e]+$/.test(item.provider_connection_id) ||
      !(item.outbound_number === null || phone(item.outbound_number)) ||
      !Array.isArray(item.published_routes) ||
      ids.has(item.id) ||
      names.has(item.name)
    )
      throw invalid();
    ids.add(item.id);
    names.add(item.name);
    routeCount += item.published_routes.length;
    if (routeCount > 500) throw invalid();
    const routes = item.published_routes.map((route): PublishedPhoneRoute => {
      if (
        !record(route) ||
        !phone(route.number) ||
        !text(route.call_spec_id) ||
        !text(route.call_spec_name, 4096) ||
        typeof route.call_spec_revision !== "number" ||
        !Number.isSafeInteger(route.call_spec_revision) ||
        route.call_spec_revision < 1 ||
        !text(route.participant_ref) ||
        typeof route.ambiguous !== "boolean"
      )
        throw invalid();
      return {
        number: route.number,
        call_spec_id: route.call_spec_id,
        call_spec_name: route.call_spec_name,
        call_spec_revision: route.call_spec_revision,
        participant_ref: route.participant_ref,
        ambiguous: route.ambiguous,
      };
    });
    return {
      id: item.id,
      name: item.name,
      provider_connection_id: item.provider_connection_id,
      outbound_number: item.outbound_number,
      published_routes: routes,
    };
  });
  return { applications, truncated: value.truncated };
}
