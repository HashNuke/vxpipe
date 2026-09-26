import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const homepage = readFileSync(join(root, 'src/content/docs/index.mdx'), 'utf8');
const landingCss = readFileSync(join(root, 'src/styles/landing.css'), 'utf8');

test('landing backdrop spans the full top stage in both themes', () => {
  assert.match(
    landingCss,
    /html\[data-has-hero\] body\s*\{[^}]*background-image:/s,
    'the page, not the hero text box, must own the landing backdrop',
  );
  assert.match(
    landingCss,
    /html\[data-theme=['"]dark['"]\]\[data-has-hero\]/,
    'the landing backdrop must define a dark-theme treatment',
  );
  assert.match(
    landingCss,
    /html\[data-theme=['"]light['"]\]\[data-has-hero\]/,
    'the landing backdrop must define a light-theme treatment',
  );
  assert.match(
    landingCss,
    /\.sl-container > div\.hero\s*\{[^}]*background:\s*transparent/s,
    'the hero must not retain its old rectangular background',
  );
  assert.doesNotMatch(
    landingCss,
    /\.sl-container > div\.hero::before/,
    'the ripple field must not be clipped to the hero text box',
  );
  assert.match(
    landingCss,
    /repeating-radial-gradient\(\s*ellipse 78rem 48rem at -4% 30rem/s,
    'the selected open wave must radiate into the stage from beyond its left edge',
  );
  assert.doesNotMatch(
    landingCss,
    /ellipse 76rem 31rem at 50% 31rem/,
    'the old centered ripple treatment must be replaced',
  );
});

test('homepage keeps its current hero actions and section order', () => {
  assert.match(homepage, /title: Voice agents you own\./);
  assert.match(homepage, /tagline: VxPipe runs the whole call/);

  for (const badge of ['Apache 2.0', 'Self-hostable', 'Built on Elixir & OTP', 'Pre-release']) {
    assert.match(homepage, new RegExp(badge), `trust row must include ${badge}`);
  }

  const heroCtas = homepage.slice(
    homepage.indexOf('<div className="hero-cta">'),
    homepage.indexOf('<CallRoomVisual'),
  );
  assert.equal((heroCtas.match(/<LinkButton /g) ?? []).length, 2);
  assert.match(heroCtas, /href="#quickstart"[\s\S]*>\s*Get started/);
  assert.match(heroCtas, /href="https:\/\/github\.com\/HashNuke\/vxpipe"[\s\S]*>\s*Star on GitHub/);
  assert.ok(homepage.indexOf('trust-cloud') < homepage.indexOf('<CallRoomVisual'));

  const sections = [
    'Why VxPipe',
    'How it works',
    'Features',
    'How VxPipe compares',
    'Quickstart',
    'FAQ',
  ];
  let previous = -1;
  for (const section of sections) {
    const position = homepage.indexOf(`## ${section}`);
    assert.ok(position > previous, `${section} must follow the previous section`);
    previous = position;
  }

  for (const group of ['Connect', 'Orchestrate', 'Operate', 'Own']) {
    assert.match(homepage, new RegExp(`<h3 id="feature-[^"]+">${group}</h3>`));
  }
  assert.match(homepage, /className="quickstart-cta"/);
});

test('landing copy avoids em dashes', () => {
  const visual = readFileSync(join(root, 'src/components/CallRoomVisual.tsx'), 'utf8');
  assert.doesNotMatch(homepage, /—/, 'homepage copy must not use em dashes');
  assert.doesNotMatch(visual, /—/, 'call-room visual copy must not use em dashes');
});

test('provider wall lists providers by name only, in two groups', () => {
  const providers = homepage.slice(homepage.indexOf('<div className="provider-groups">'), homepage.indexOf('## How VxPipe compares'));
  assert.ok(homepage.indexOf('## Features') < homepage.indexOf('<div className="provider-groups">'));
  assert.match(providers, /<h2 id="ai-providers">Supported AI Providers<\/h2>/);
  assert.match(providers, /<h2 id="telephony-providers">Supported Telephony Providers<\/h2>/);
  assert.doesNotMatch(providers, /<small>|GPT-Live|Gemini Live|data-status/, 'no model names, taglines, or status tiers');
});

test('comparison and steps stay concise', () => {
  const compare = homepage.slice(homepage.indexOf('## How VxPipe compares'), homepage.indexOf('## Quickstart'));
  assert.match(compare, /\| Per-minute fee \|/);
  assert.doesNotMatch(compare, /Usually a per-minute/);

  const describe = homepage.slice(homepage.indexOf('**Describe the call.**'), homepage.indexOf('**Take calls.**'));
  const body = describe.replace('**Describe the call.**', '').replace(/^\s*\d\.\s*$/m, '').trim();
  assert.ok(body.split(/\s+/).length <= 12, `describe step must be one short sentence: ${body}`);
});
