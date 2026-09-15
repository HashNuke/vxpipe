import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const homepage = readFileSync(join(root, 'src/content/docs/index.mdx'), 'utf8');

test('homepage hero states the product crisply and indexes capabilities', () => {
  assert.match(homepage, /tagline: .+/, 'hero must state a tagline');
  assert.doesNotMatch(
    homepage,
    /Build browser and phone agents with transport/,
    'word-salad tagline must be gone',
  );

  for (const badge of [
    'Telephony',
    'AI Providers',
    'Multi-Agent Orchestration',
    'MCP Tools',
    'Participant Policies',
    'Compliance Friendly',
    'Call Variables',
    'Call Recording',
    'Call Diagnostics',
  ]) {
    assert.match(homepage, new RegExp(badge), `capability cloud must include ${badge}`);
  }

  for (const badge of ['Apache 2.0', 'Self-hostable', 'Built on Elixir & OTP']) {
    assert.match(homepage, new RegExp(badge), `trust row must keep ${badge}`);
  }
  assert.ok(
    homepage.indexOf('Call Diagnostics') < homepage.indexOf('Apache 2.0'),
    'trust badges must close the feature list',
  );

  assert.ok(
    homepage.indexOf('capability-cloud') < homepage.indexOf('<CallRoomVisual'),
    'capability cloud must lead into the room visual',
  );
});
