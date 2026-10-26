import { expect, test } from "vitest";
import { directoryPageFixture } from "./directoryPageFixture";
import { directoryRequest } from "./directoryRequest";
import { catalogWithProviders, expandedRemoteCatalog } from "./remoteDirectory";

test.each(["X-VxPipe-Version", "x-vxpipe-version", "X-VXPIPE-VERSION"])("directory version filtering accepts %s", name => {
  const request = { ...directoryRequest({ query: "Example" }), headers: { [name]: "0.1.0" } };
  const page = directoryPageFixture(catalogWithProviders(expandedRemoteCatalog, true), request);

  expect(page?.installation_version).toBe("0.1.0");
  expect(page?.items.map(item => item.name)).toEqual(["Example knowledge"]);
  expect(page?.pagination.total_items).toBe(1);
});
