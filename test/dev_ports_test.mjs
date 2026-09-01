import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import {
  appendFileSync,
  mkdtempSync,
  mkdirSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";

import {
  environmentForProcesses,
  findCandidatePortBlock,
  parseEnvironment,
  parseProcessNames,
  portsForProcesses,
} from "../bin/dev-ports.mjs";

test("parseProcessNames returns Procfile processes in declaration order", () => {
  const procfile = `
# Development processes
docs: npm --prefix docs run dev
samples_backend: npm --prefix samples run dev:backend

samples_frontend: npm --prefix samples run dev:frontend
storybook: npm --prefix samples run storybook
`;

  assert.deepEqual(parseProcessNames(procfile), [
    "docs",
    "samples_backend",
    "samples_frontend",
    "storybook",
  ]);
});

test("environmentForProcesses assigns one contiguous port per process", () => {
  assert.deepEqual(
    environmentForProcesses(
      ["docs", "samples_backend", "samples_frontend", "storybook"],
      4_100,
    ),
    {
      DEV_PORT_BASE: "4100",
      DEV_PORT_COUNT: "4",
      DEV_PORT_DOCS: "4100",
      DEV_PORT_MODE: "worktree",
      DEV_PORT_SAMPLES_BACKEND: "4101",
      DEV_PORT_SAMPLES_FRONTEND: "4102",
      DEV_PORT_STORYBOOK: "4103",
    },
  );
});

test("findCandidatePortBlock skips reserved and unavailable ranges", async () => {
  const checked = [];
  const available = async (ports) => {
    checked.push(ports);
    return ports[0] >= 4_106;
  };

  const basePort = await findCandidatePortBlock({
    count: 4,
    isAvailable: available,
    reservedPorts: new Set([4_102]),
    startPort: 4_100,
  });

  assert.equal(basePort, 4_106);
  assert.deepEqual(checked, [
    [4_103, 4_104, 4_105, 4_106],
    [4_104, 4_105, 4_106, 4_107],
    [4_105, 4_106, 4_107, 4_108],
    [4_106, 4_107, 4_108, 4_109],
  ]);
});

test("parseEnvironment reads generated assignments without evaluating shell", () => {
  const environment = parseEnvironment(`
# Generated file
DEV_PORT_BASE=4100
DEV_PORT_DOCS=4100
IGNORED='not evaluated'
`);

  assert.deepEqual(environment, {
    DEV_PORT_BASE: "4100",
    DEV_PORT_DOCS: "4100",
    IGNORED: "'not evaluated'",
  });
});

test("portsForProcesses supports stable non-contiguous primary defaults", () => {
  const environment = {
    DEV_PORT_COUNT: "4",
    DEV_PORT_DOCS: "4321",
    DEV_PORT_MODE: "default",
    DEV_PORT_SAMPLES_BACKEND: "4100",
    DEV_PORT_SAMPLES_FRONTEND: "5173",
    DEV_PORT_STORYBOOK: "6006",
  };

  assert.deepEqual(
    portsForProcesses(environment, [
      "docs",
      "samples_backend",
      "samples_frontend",
      "storybook",
    ]),
    [4_321, 4_100, 5_173, 6_006],
  );
});

test("CLI keeps primary defaults and assigns distinct linked-worktree blocks", () => {
  const fixtureRoot = mkdtempSync(join(tmpdir(), "vxpipe-dev-ports-"));
  const primary = join(fixtureRoot, "primary");
  const firstWorktree = join(fixtureRoot, "first");
  const secondWorktree = join(fixtureRoot, "second");
  const scriptPath = new URL("../bin/dev-ports.mjs", import.meta.url);
  const procfile = [
    "docs: run docs",
    "samples_backend: run backend",
    "samples_frontend: run frontend",
    "storybook: run storybook",
    "",
  ].join("\n");
  const defaults = [
    "DEV_PORT_MODE=default",
    "DEV_PORT_COUNT=4",
    "DEV_PORT_DOCS=4321",
    "DEV_PORT_SAMPLES_BACKEND=4100",
    "DEV_PORT_SAMPLES_FRONTEND=5173",
    "DEV_PORT_STORYBOOK=6006",
    "",
  ].join("\n");

  try {
    mkdirSync(primary);
    execFileSync("git", ["init", "--quiet", primary]);
    execFileSync("git", ["-C", primary, "config", "user.email", "test@example.com"]);
    execFileSync("git", ["-C", primary, "config", "user.name", "Test"]);
    writeFileSync(join(primary, "Procfile.dev"), procfile);
    writeFileSync(join(primary, ".env.dev.defaults"), defaults);
    execFileSync("git", ["-C", primary, "add", "Procfile.dev", ".env.dev.defaults"]);
    execFileSync("git", ["-C", primary, "commit", "--quiet", "-m", "fixture"]);

    execFileSync(process.execPath, [scriptPath.pathname, "assign", primary]);
    const primaryEnvironment = parseEnvironment(
      readFileSync(join(primary, ".env.dev"), "utf8"),
    );

    assert.deepEqual(
      portsForProcesses(primaryEnvironment, [
        "docs",
        "samples_backend",
        "samples_frontend",
        "storybook",
      ]),
      [4_321, 4_100, 5_173, 6_006],
    );
    appendFileSync(join(primary, ".env.dev"), "SAMPLES_FIXTURE_MODE=local\n");
    execFileSync(process.execPath, [scriptPath.pathname, "assign", primary]);
    assert.equal(
      parseEnvironment(readFileSync(join(primary, ".env.dev"), "utf8"))
        .SAMPLES_FIXTURE_MODE,
      "local",
    );

    execFileSync("git", [
      "-C",
      primary,
      "worktree",
      "add",
      "--quiet",
      "-b",
      "first-worktree",
      firstWorktree,
    ]);
    execFileSync(process.execPath, [scriptPath.pathname, "assign", firstWorktree], {
      env: { ...process.env, VXPIPE_DEV_PORT_START: "55000" },
    });
    const firstEnvironment = parseEnvironment(
      readFileSync(join(firstWorktree, ".env.dev"), "utf8"),
    );
    const firstPorts = portsForProcesses(firstEnvironment, [
      "docs",
      "samples_backend",
      "samples_frontend",
      "storybook",
    ]);

    assert.equal(firstEnvironment.DEV_PORT_MODE, "worktree");
    assert.deepEqual(firstPorts, [55_000, 55_001, 55_002, 55_003]);

    execFileSync("git", [
      "-C",
      primary,
      "worktree",
      "add",
      "--quiet",
      "-b",
      "second-worktree",
      secondWorktree,
    ]);
    execFileSync(process.execPath, [scriptPath.pathname, "assign", secondWorktree], {
      env: { ...process.env, VXPIPE_DEV_PORT_START: "55000" },
    });
    const secondEnvironment = parseEnvironment(
      readFileSync(join(secondWorktree, ".env.dev"), "utf8"),
    );

    assert.deepEqual(
      portsForProcesses(secondEnvironment, [
        "docs",
        "samples_backend",
        "samples_frontend",
        "storybook",
      ]),
      [55_004, 55_005, 55_006, 55_007],
    );
    assert.equal(
      execFileSync(process.execPath, [scriptPath.pathname, "check", secondWorktree], {
        encoding: "utf8",
      }),
      join(secondWorktree, ".env.dev"),
    );
  } finally {
    rmSync(fixtureRoot, { force: true, recursive: true });
  }
});
