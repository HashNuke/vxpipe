import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const homepage = readFileSync(join(root, 'src/content/docs/index.mdx'), 'utf8');
const landingCss = readFileSync(join(root, 'src/styles/landing.css'), 'utf8');

test('homepage hero states the product crisply and presents the feature set', () => {
  assert.match(homepage, /tagline: .+/, 'hero must state a tagline');
  assert.doesNotMatch(
    homepage,
    /Build browser and phone agents with transport/,
    'word-salad tagline must be gone',
  );

  for (const badge of ['Apache 2.0', 'Self-hostable', 'Built on Elixir & OTP']) {
    assert.match(homepage, new RegExp(badge), `trust row must keep ${badge}`);
  }
  assert.match(homepage, /className="trust-cloud"/, 'project trust badges need a named group');

  const heroCtas = homepage.slice(homepage.indexOf('<div className="hero-cta">'), homepage.indexOf('<CallRoomVisual'));
  assert.equal((heroCtas.match(/<LinkButton /g) ?? []).length, 3, 'hero must expose three CTAs');
  assert.match(heroCtas, /href="#quickstart"[\s\S]*>\s*Get started/);
  assert.match(heroCtas, /href="\/en\/docs\/"[\s\S]*>\s*Documentation/);
  assert.match(heroCtas, /href="https:\/\/github\.com\/HashNuke\/vxpipe"[\s\S]*>\s*View on GitHub/);

  for (const badge of [
    'Telephony',
    'WebRTC',
    'AI Providers',
    'MCP Tools',
    'Multi-Agent Orchestration',
    'Call Policies',
    'Compliance friendly',
    'Call Recording',
    'Call Variables',
    'Call Diagnostics',
    'Extendable',
    'Self-hostable',
    'Built on Elixir &amp; OTP',
  ]) {
    assert.match(homepage, new RegExp(badge), `feature cards must include ${badge}`);
  }

  assert.ok(
    homepage.indexOf('trust-cloud') < homepage.indexOf('<CallRoomVisual'),
    'trust badges must stay near the hero before the room visual',
  );

  assert.match(homepage, /## Features/, 'feature section must be titled Features');
  assert.doesNotMatch(
    homepage,
    /## Transport and pipeline, together/,
    'old architecture heading must be replaced',
  );

  assert.match(homepage, /## Quickstart/, 'homepage must retain a Quickstart section');
  const quickstart = homepage.slice(homepage.indexOf('## Quickstart'), homepage.indexOf('provider-groups'));
  assert.match(quickstart, /<LinkButton href="\/en\/docs\/"[^>]*>\s*View documentation/);

  const features = homepage.slice(homepage.indexOf('## Features'), homepage.indexOf('## Quickstart'));
  assert.equal(
    (features.match(/<article className="card feature-card">/g) ?? []).length,
    13,
    'Features must contain thirteen feature cards',
  );
  for (const copy of [
    'Connect to and configure telephony providers for calls.',
    'Setup calls via web, without telephony.',
    'Use AI models and providers of your choice for Text-to-Speech, Speech-to-Text and LLMs.',
    'Provide your voice agents with MCP tools to access various services.',
    'Setup agents with different goals and transfer calls between agents.',
    'Specify rules for calls when participants enter or exit the call.',
    'Play recording notices and AI disclosures before the conversation begins.',
    'Record calls, and stream them directly to your S3 compatible storage buckets.',
    'Collect information from the user, just like filling out a form.',
    'Ships with tools to help you inspect and diagnose calls and voice agent issues.',
    'Extend VxPipe with your own providers, tools, and integrations.',
    'Run VxPipe on your own infrastructure. Detailed instructions are available.',
    "We build on tools with good abstractions so you can have a good night's sleep.",
  ]) {
    assert.match(features, new RegExp(copy.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')), `feature copy must include: ${copy}`);
  }
  for (const title of [
    'Telephony',
    'WebRTC',
    'AI Providers',
    'MCP Tools',
    'Multi-Agent Orchestration',
    'Call Variables',
    'Call Policies',
    'Call Recording',
    'Compliance friendly',
    'Call Diagnostics',
    'Extendable',
    'Self-hostable',
    'Built on Elixir &amp; OTP',
  ]) {
    assert.match(features, new RegExp(`<h3>${title}</h3>`), `feature card title must be an H3: ${title}`);
  }
  assert.match(
    landingCss,
    /\.features \.feature-card h3\s*\{[^}]*font-size:\s*0\.875rem/s,
    'feature card titles must keep the compact card scale',
  );
  assert.match(
    landingCss,
    /\.features \.feature-card-title\s*\{[^}]*align-items:\s*center/s,
    'feature card icons and titles must share a centered vertical alignment',
  );
  assert.match(
    landingCss,
    /\.sl-markdown-content h2\s*\{[^}]*font-size:\s*1\.5rem[^}]*font-weight:\s*600/s,
    'homepage section headings must have a stronger visual hierarchy',
  );
});
