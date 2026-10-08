// Representative defaults captured from the backend catalog for stories and tests.
import fixture from "./fixtures/modelCatalog.json";
import { parseModelCatalog } from "./modelCatalog";
export const modelCatalogFixture = parseModelCatalog(fixture);
