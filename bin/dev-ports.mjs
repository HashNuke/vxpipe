#!/usr/bin/env node

import { execFileSync } from "node:child_process";
import {
  existsSync,
  readFileSync,
  realpathSync,
  renameSync,
  writeFileSync,
} from "node:fs";
import { createServer } from "node:net";
import { basename, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const defaultStartPort = 4_100;
const environmentFileName = ".env.dev";
const defaultEnvironmentFileName = ".env.dev.defaults";

export function parseProcessNames(procfile) {
  const names = [];

  for (const [index, sourceLine] of procfile.split(/\r?\n/u).entries()) {
    const line = sourceLine.trim();

    if (line === "" || line.startsWith("#")) {
      continue;
    }

    const match = /^([A-Za-z0-9_-]+):\s+\S/u.exec(line);

    if (match === null) {
      throw new Error(`Invalid Procfile.dev entry on line ${index + 1}`);
    }

    const name = match[1];

    if (names.includes(name)) {
      throw new Error(`Duplicate Procfile.dev process: ${name}`);
    }

    names.push(name);
  }

  if (names.length === 0) {
    throw new Error("Procfile.dev does not define any processes");
  }

  return names;
}

function variableName(processName) {
  return `DEV_PORT_${processName.replaceAll(/[^A-Za-z0-9]/gu, "_").toUpperCase()}`;
}

export function environmentForProcesses(processNames, basePort) {
  const environment = {
    DEV_PORT_BASE: String(basePort),
    DEV_PORT_COUNT: String(processNames.length),
    DEV_PORT_MODE: "worktree",
  };

  for (const [index, processName] of processNames.entries()) {
    const name = variableName(processName);

    if (Object.hasOwn(environment, name)) {
      throw new Error(`Procfile.dev process names collide as ${name}`);
    }

    environment[name] = String(basePort + index);
  }

  return environment;
}

export function parseEnvironment(contents) {
  const environment = {};

  for (const sourceLine of contents.split(/\r?\n/u)) {
    const line = sourceLine.trim();

    if (line === "" || line.startsWith("#")) {
      continue;
    }

    const separator = line.indexOf("=");

    if (separator <= 0) {
      continue;
    }

    environment[line.slice(0, separator)] = line.slice(separator + 1);
  }

  return environment;
}

export function portsForProcesses(environment, processNames) {
  const count = Number.parseInt(environment.DEV_PORT_COUNT ?? "", 10);

  if (count !== processNames.length) {
    throw new Error("Development port count does not match Procfile.dev");
  }

  const ports = processNames.map((processName) => {
    const name = variableName(processName);
    const port = Number.parseInt(environment[name] ?? "", 10);

    if (!Number.isInteger(port) || port < 1 || port > 65_535) {
      throw new Error(`Missing or invalid development port: ${name}`);
    }

    return port;
  });

  if (new Set(ports).size !== ports.length) {
    throw new Error("Development ports must be unique");
  }

  return ports;
}

function range(basePort, count) {
  return Array.from({ length: count }, (_, index) => basePort + index);
}

export async function findCandidatePortBlock({
  count,
  isAvailable,
  reservedPorts,
  startPort = defaultStartPort,
}) {
  if (!Number.isInteger(count) || count < 1) {
    throw new Error("The development process count must be a positive integer");
  }

  const lastBasePort = 65_535 - count + 1;

  for (let basePort = startPort; basePort <= lastBasePort; basePort += 1) {
    const ports = range(basePort, count);

    if (ports.some((port) => reservedPorts.has(port))) {
      continue;
    }

    if (await isAvailable(ports)) {
      return basePort;
    }
  }

  throw new Error(`No contiguous block of ${count} development ports is available`);
}

function listen(port) {
  return new Promise((resolveListen, rejectListen) => {
    const server = createServer();

    server.once("error", rejectListen);
    server.listen({ host: "0.0.0.0", port, exclusive: true }, () => {
      server.removeListener("error", rejectListen);
      resolveListen(server);
    });
  });
}

async function portsAvailable(ports) {
  const servers = [];

  try {
    for (const port of ports) {
      servers.push(await listen(port));
    }

    return true;
  } catch (error) {
    if (error?.code === "EADDRINUSE" || error?.code === "EACCES") {
      return false;
    }

    throw error;
  } finally {
    await Promise.all(
      servers.map(
        (server) =>
          new Promise((resolveClose, rejectClose) => {
            server.close((error) => {
              if (error === undefined) {
                resolveClose();
              } else {
                rejectClose(error);
              }
            });
          }),
      ),
    );
  }
}

function worktreePaths(projectRoot) {
  const output = execFileSync(
    "git",
    ["-C", projectRoot, "worktree", "list", "--porcelain", "-z"],
    { encoding: "utf8" },
  );

  return output
    .split("\0")
    .filter((entry) => entry.startsWith("worktree "))
    .map((entry) => entry.slice("worktree ".length));
}

function gitPath(projectRoot, argument) {
  const output = execFileSync(
    "git",
    ["-C", projectRoot, "rev-parse", "--path-format=absolute", argument],
    { encoding: "utf8" },
  ).trim();

  return realpathSync(output);
}

function linkedWorktree(projectRoot) {
  return gitPath(projectRoot, "--git-dir") !== gitPath(projectRoot, "--git-common-dir");
}

function defaultEnvironment(projectRoot, processNames) {
  const environmentPath = join(projectRoot, defaultEnvironmentFileName);
  const environment = parseEnvironment(readFileSync(environmentPath, "utf8"));

  if (environment.DEV_PORT_MODE !== "default") {
    throw new Error(`${defaultEnvironmentFileName} must use DEV_PORT_MODE=default`);
  }

  portsForProcesses(environment, processNames);
  return environment;
}

function reservedPortsForOtherWorktrees(projectRoot) {
  const currentWorktree = realpathSync(projectRoot);
  const reservedPorts = new Set();

  for (const worktreePath of worktreePaths(projectRoot)) {
    if (realpathSync(worktreePath) === currentWorktree) {
      continue;
    }

    const environmentPath = join(worktreePath, environmentFileName);

    if (!existsSync(environmentPath)) {
      continue;
    }

    const environment = parseEnvironment(readFileSync(environmentPath, "utf8"));

    for (const [name, value] of Object.entries(environment)) {
      if (!name.startsWith("DEV_PORT_") || name === "DEV_PORT_COUNT") {
        continue;
      }

      const port = Number.parseInt(value, 10);

      if (Number.isInteger(port) && port >= 1 && port <= 65_535) {
        reservedPorts.add(port);
      }
    }
  }

  return reservedPorts;
}

function configuredBasePort(environment, processNames, reservedPorts) {
  if (environment.DEV_PORT_MODE !== "worktree") {
    return undefined;
  }

  const basePort = Number.parseInt(environment.DEV_PORT_BASE ?? "", 10);
  let ports;

  if (!Number.isInteger(basePort) || basePort < 1) {
    return undefined;
  }

  try {
    ports = portsForProcesses(environment, processNames);
  } catch {
    return undefined;
  }

  const expectedEnvironment = environmentForProcesses(processNames, basePort);

  for (const [name, value] of Object.entries(expectedEnvironment)) {
    if (environment[name] !== value) {
      return undefined;
    }
  }

  if (ports.some((port) => reservedPorts.has(port))) {
    return undefined;
  }

  return basePort;
}

function renderEnvironment(environment) {
  const assignments = Object.entries(environment).map(
    ([name, value]) => `${name}=${value}`,
  );

  return [
    "# Generated by bin/setup for Goreman and its child processes. Do not commit.",
    ...assignments,
    "",
  ].join("\n");
}

function writeEnvironment(environmentPath, environment) {
  const temporaryPath = `${environmentPath}.${process.pid}.tmp`;

  writeFileSync(temporaryPath, renderEnvironment(environment), {
    encoding: "utf8",
    mode: 0o600,
  });
  renameSync(temporaryPath, environmentPath);
}

function preserveLocalEnvironment(generatedEnvironment, existingEnvironment) {
  const environment = { ...generatedEnvironment };

  for (const [name, value] of Object.entries(existingEnvironment)) {
    if (!name.startsWith("DEV_PORT_")) {
      environment[name] = value;
    }
  }

  return environment;
}

function printAllocation(processNames, ports, description) {
  process.stdout.write(`==> Using ${description} development ports\n`);

  for (const [index, processName] of processNames.entries()) {
    process.stdout.write(`    ${processName}: ${ports[index]}\n`);
  }
}

async function assign(projectRoot) {
  const procfilePath = join(projectRoot, "Procfile.dev");
  const environmentPath = join(projectRoot, environmentFileName);
  const processNames = parseProcessNames(readFileSync(procfilePath, "utf8"));
  const existingEnvironment = existsSync(environmentPath)
    ? parseEnvironment(readFileSync(environmentPath, "utf8"))
    : {};

  if (!linkedWorktree(projectRoot)) {
    const environment = preserveLocalEnvironment(
      defaultEnvironment(projectRoot, processNames),
      existingEnvironment,
    );

    writeEnvironment(environmentPath, environment);
    printAllocation(
      processNames,
      portsForProcesses(environment, processNames),
      "default",
    );
    return;
  }

  const reservedPorts = reservedPortsForOtherWorktrees(projectRoot);
  const defaults = defaultEnvironment(projectRoot, processNames);

  for (const port of portsForProcesses(defaults, processNames)) {
    reservedPorts.add(port);
  }

  const existingBasePort = configuredBasePort(
    existingEnvironment,
    processNames,
    reservedPorts,
  );

  if (existingBasePort !== undefined) {
    printAllocation(
      processNames,
      range(existingBasePort, processNames.length),
      "reserved worktree",
    );
    return;
  }

  const configuredStartPort = Number.parseInt(
    process.env.VXPIPE_DEV_PORT_START ?? String(defaultStartPort),
    10,
  );

  if (!Number.isInteger(configuredStartPort) || configuredStartPort < 1) {
    throw new Error("VXPIPE_DEV_PORT_START must be a positive integer");
  }

  const basePort = await findCandidatePortBlock({
    count: processNames.length,
    isAvailable: portsAvailable,
    reservedPorts,
    startPort: configuredStartPort,
  });
  const environment = preserveLocalEnvironment(
    environmentForProcesses(processNames, basePort),
    existingEnvironment,
  );

  writeEnvironment(environmentPath, environment);
  printAllocation(
    processNames,
    range(basePort, processNames.length),
    "new worktree",
  );
}

async function check(projectRoot) {
  const procfilePath = join(projectRoot, "Procfile.dev");
  const processNames = parseProcessNames(readFileSync(procfilePath, "utf8"));
  const isLinkedWorktree = linkedWorktree(projectRoot);
  const environmentPath = join(projectRoot, environmentFileName);

  if (!existsSync(environmentPath)) {
    throw new Error(`${environmentFileName} is missing; run bin/setup first`);
  }

  const environment = parseEnvironment(readFileSync(environmentPath, "utf8"));
  let ports;

  if (isLinkedWorktree) {
    const reservedPorts = reservedPortsForOtherWorktrees(projectRoot);
    const defaults = defaultEnvironment(projectRoot, processNames);

    for (const port of portsForProcesses(defaults, processNames)) {
      reservedPorts.add(port);
    }

    const basePort = configuredBasePort(environment, processNames, reservedPorts);

    if (basePort === undefined) {
      throw new Error(
        `${environmentFileName} does not match Procfile.dev; run bin/setup again`,
      );
    }

    ports = range(basePort, processNames.length);
  } else {
    if (environment.DEV_PORT_MODE !== "default") {
      throw new Error(`${defaultEnvironmentFileName} is invalid`);
    }

    ports = portsForProcesses(environment, processNames);
  }

  if (!(await portsAvailable(ports))) {
    throw new Error(
      `One or more development ports are unavailable: ${ports.join(", ")}`,
    );
  }

  process.stdout.write(environmentPath);
}

async function main() {
  const command = process.argv[2];
  const projectRoot = resolve(process.argv[3] ?? join(import.meta.dirname, ".."));

  if (command === "assign") {
    await assign(projectRoot);
    return;
  }

  if (command === "check") {
    await check(projectRoot);
    return;
  }

  throw new Error(`Usage: ${basename(process.argv[1])} assign|check [project-root]`);
}

if (resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  main().catch((error) => {
    process.stderr.write(`bin/dev-ports: ${error.message}\n`);
    process.exitCode = 1;
  });
}
