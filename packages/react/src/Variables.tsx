import type { JsonValue, VariableSnapshot } from "@vxpipe/core";

function displayValue(value: JsonValue) {
  if (value === null) return <span className="vx-variable-empty">null</span>;
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "string" || typeof value === "number")
    return String(value);
  return <pre>{JSON.stringify(value, null, 2)}</pre>;
}

function entries(value: JsonValue): readonly [string, JsonValue][] {
  if (value !== null && !Array.isArray(value) && typeof value === "object")
    return Object.entries(value);
  return [["value", value]];
}

export function Variables({ snapshot }: { snapshot: VariableSnapshot | null }) {
  if (!snapshot)
    return (
      <section className="vx-variables vx-empty" aria-label="Call variables">
        <h2>Variables unavailable</h2>
      </section>
    );

  const sections = Object.entries(snapshot.sections);
  return (
    <section className="vx-variables" aria-label="Call variables">
      {sections.length === 0 ? (
        <div className="vx-empty">
          <h2>No variables</h2>
        </div>
      ) : (
        <div className="vx-variable-sections">
          {sections.map(([name, section]) => (
            <article className="vx-variable-section" key={name}>
              <header>
                <h2>{name}</h2>
              </header>
              <dl>
                {entries(section.value).map(([key, value]) => (
                  <div key={key}>
                    <dt>{key}</dt>
                    <dd>{displayValue(value)}</dd>
                  </div>
                ))}
              </dl>
            </article>
          ))}
        </div>
      )}
    </section>
  );
}
