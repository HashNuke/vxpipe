import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (rel) => readFileSync(join(root, rel), 'utf8');

test('homepage renders a call-room visual built on room terminology', () => {
  assert.equal(
    existsSync(join(root, 'src/components/CallRoomVisual.astro')),
    true,
    'expected src/components/CallRoomVisual.astro to exist',
  );

  const homepage = read('src/content/docs/index.mdx');
  assert.match(homepage, /CallRoomVisual/, 'homepage must render CallRoomVisual');

  const visual = read('src/components/CallRoomVisual.astro');
  for (const term of ['call room', 'caller', 'agent', 'capabilit', 'participant']) {
    assert.match(
      visual.toLowerCase(),
      new RegExp(term),
      `visual must use room terminology: ${term}`,
    );
  }
  assert.match(
    visual.toLowerCase(),
    /pseudo.?wire|audio ?in/,
    'caller audio must arrive over an external pseudo wire',
  );
});
