import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const read = (rel) => readFileSync(join(root, rel), 'utf8');

test('homepage renders a static React call-room visual built on room terminology', () => {
  assert.equal(
    existsSync(join(root, 'src/components/CallRoomVisual.tsx')),
    true,
    'expected src/components/CallRoomVisual.tsx to exist',
  );
  assert.equal(
    existsSync(join(root, 'src/components/CallRoomVisual.astro')),
    false,
    'astro prototype must be replaced by the React component',
  );

  const homepage = read('src/content/docs/index.mdx');
  assert.match(homepage, /<CallRoomVisual/, 'homepage must render CallRoomVisual');
  assert.doesNotMatch(
    homepage,
    /<CallRoomVisual[^>]*client:/,
    'homepage visual must render statically without hydration',
  );

  const visual = read('src/components/CallRoomVisual.tsx');

  // Props seam for the future live monitor, with static defaults for docs.
  assert.match(visual, /Props/, 'component must expose a props interface');
  assert.match(visual, /profiles/i, 'component must accept agent profiles');

  // Room manages the call: authority and room-owned services lead.
  for (const term of [
    'call room',
    'call variables',
    'transcripts',
    'call recording',
    'policies',
    'room mixer',
    'caller',
    'agent',
    'participant',
    'capabilit',
  ]) {
    assert.match(
      visual.toLowerCase(),
      new RegExp(term),
      `visual must use room terminology: ${term}`,
    );
  }

  // Newcomers read plain language, not internal architecture names.
  for (const jargon of ['room authority', 'transcript router', 'managed by the room']) {
    assert.doesNotMatch(visual.toLowerCase(), new RegExp(jargon), `visual must not show jargon: ${jargon}`);
  }

  // A caption narrates the handoff story in step with the deck.
  assert.match(visual, /crv-story/, 'visual must narrate the call story');
  assert.equal(
    (visual.match(/storyline: '/g) ?? []).length,
    3,
    'each default profile must carry one story line',
  );

  // Audiogram halo replaces header equalizer bars.
  assert.doesNotMatch(visual, /Equalizer|crv-eq/, 'equalizer bars must be gone');
  assert.match(visual, /crv-ring/, 'caller avatar must carry an audiogram ring');

  // No pseudo-wire / audio-in on the caller card.
  assert.doesNotMatch(visual, /crv-ingress/, 'audio ingress block must be gone');
  assert.doesNotMatch(
    visual,
    /crv-ingress-flow/,
    'audio-in must not carry a separate line-in animation',
  );
  assert.doesNotMatch(
    visual.toLowerCase(),
    /pseudo wire/,
    'pseudo wire must not appear on the caller card',
  );
  assert.doesNotMatch(
    visual.toLowerCase(),
    /audio in/,
    'audio-in must not appear on the caller card',
  );

  // Caller number rides beside speech-to-text; no telephony row.
  const callerAt = visual.indexOf('aria-label="caller participant"');
  const agentAt = visual.indexOf('aria-label="agent profiles"');
  assert.ok(callerAt !== -1 && agentAt > callerAt, 'caller and agent sections must exist');
  const callerSection = visual.slice(callerAt, agentAt);
  assert.doesNotMatch(
    callerSection.toLowerCase(),
    /telephony/,
    'telephony tag must be gone',
  );
  assert.match(
    callerSection,
    /\+\d[\d\s()\-]{6,}/,
    'caller must show an indicative phone number',
  );
  assert.match(
    callerSection,
    /crv-cap--tel[\s\S]{0,300}?<CallIcon/,
    'number badge must sit beside speech-to-text with a call icon',
  );
  assert.match(
    visual,
    /function CallIcon[\s\S]{0,800}?<svg/,
    'call icon must draw vector artwork',
  );

  // No MCP tools badge on the concierge card.
  assert.doesNotMatch(visual, /MCP tools/, 'MCP tools badge must be gone');

  // Deck: profile cards stacked behind one another, front card active.
  const roster = visual.match(/id: '[abc]',/g) ?? [];
  assert.equal(roster.length, 3, `expected 3 default agent profiles, found ${roster.length}`);
  assert.match(visual, /crv-deck/, 'profiles must stack like a deck of cards');
  assert.doesNotMatch(visual, /one active/, 'no one-active label; the front card speaks');

  const css = read('src/styles/call-room.css');
  assert.match(
    css,
    /html\[data-theme=['"]dark['"]\] \.crv\s*\{[^}]*--crv-surface:\s*#[0-9a-f]{6}/s,
    'dark mode must give the call-room visual an opaque surface',
  );
  assert.match(
    css,
    /html\[data-theme=['"]light['"]\] \.crv\s*\{[^}]*--crv-surface:\s*#[0-9a-f]{6}/s,
    'light mode must give the call-room visual an opaque surface',
  );
  assert.match(
    css,
    /crv-deck-slot\s*\{[^}]*?0%, 30%\s*\{[^}]*transform:\s*translate\(0,\s*0\)/s,
    'front card must sit top-left with the deck cascading down-right',
  );
  assert.match(
    css,
    /grayscale\(var\(--dim\)\)/,
    'inactive badges must grey out via shared dim state',
  );
  assert.match(
    css,
    /\.crv-profile\s+\.crv-cap\s*\{[^}]*opacity:\s*calc\(1\s*-\s*var\(--dim/,
    'inactive badges must hide via shared dim state',
  );
  assert.match(
    css,
    /\.crv-grid\s*\{[^}]*align-items:\s*start/s,
    'desktop grid must top-align cards so caller meets the active agent card',
  );
  assert.match(
    css,
    /\.crv-participant--caller\s*\{[^}]*align-self:\s*start/s,
    'caller card must pin to the row top beside the active agent card',
  );
  assert.match(
    css,
    /\.crv-grid\s*>\s*\*[\s\S]{0,80}?margin:\s*0/s,
    'grid children must reset Starlight sibling margins so tops align',
  );
  assert.doesNotMatch(
    css,
    /\.crv-lane\s*\{[^}]*min-height:\s*100%/s,
    'lane must not use a circular 100% min-height that shifts it down',
  );
  assert.match(
    css,
    /\.crv-lane\s*\{[^}]*align-self:\s*start/s,
    'media lane must stay by the card headers instead of stretching with the deck',
  );
  assert.match(
    css,
    /\.crv-lane\s*\{[^}]*min-height:\s*4rem/s,
    'desktop lane must keep the mixer and audio path near the card tops',
  );
  assert.match(
    css,
    /\.crv-mixer\s*\{[^}]*top:\s*50%/s,
    'mixer must sit at the vertical middle of the lane',
  );
  assert.match(
    css,
    /\.crv-tel-number\s*\{[^}]*font-size:\s*inherit/s,
    'phone number must inherit the chip size instead of Starlight body copy',
  );
  assert.doesNotMatch(
    css,
    /\.crv-cap--tel\s*\{[^}]*font-size:\s*0\.625rem/s,
    'phone chip must not shrink below the speech-to-text size',
  );
  assert.match(
    css,
    /69%, 96%\s*\{[^}]*--dim:\s*1/s,
    'back slot must mark itself dim',
  );
  assert.doesNotMatch(css, /crv-caps-reveal/, 'deck cards must keep full content');
  assert.match(
    css,
    /crv-deck-slot\s*\{[^}]*?0%, 30%\s*\{[^}]*background-color:\s*var\(--crv-card-active\)/s,
    'front card must use the themed opaque active surface',
  );

  // Both themes own every surface; nothing dark is hard-coded into light mode.
  for (const token of ['--crv-panel', '--crv-card', '--crv-card-active', '--crv-mixer-bg', '--crv-hairline']) {
    for (const theme of ['dark', 'light']) {
      assert.match(
        css,
        new RegExp(`html\\[data-theme=['"]${theme}['"]\\] \\.crv\\s*\\{[^}]*${token}:`, 's'),
        `${theme} theme must define ${token}`,
      );
    }
  }
  for (const [rule, token] of [
    ['\\.crv-managed', '--crv-panel'],
    ['\\.crv-participant', '--crv-panel'],
    ['\\.crv-mixer', '--crv-mixer-bg'],
    ['\\.crv-profile', '--crv-card'],
    ['\\.crv-profile--a', '--crv-card-active'],
  ]) {
    assert.match(
      css,
      new RegExp(`\\n${rule}\\s*\\{[^}]*background(-color)?:\\s*var\\(${token}\\)`, 's'),
      `${rule} must paint its surface from ${token}`,
    );
  }
  assert.match(
    css,
    /crv-deck-slot\s*\{[^}]*?0%, 30%\s*\{[^}]*filter:\s*none/s,
    'front card must reset back-card blur',
  );
  assert.doesNotMatch(
    visual,
    /crv-participant--agent/,
    'agent profiles must not sit in a container card',
  );
  assert.match(
    visual,
    /crv-profile--\$\{profile\.id\}/,
    'profile cards must render per roster entry',
  );
  assert.match(
    visual.toLowerCase(),
    /one active|active agent|transfer/,
    'visual must convey one active agent at a time',
  );

  // No turn-taking centerpiece, no footer tagline, no participant badge.
  assert.doesNotMatch(visual, /caller turn|agent turn/, 'turns must not anchor the visual');
  assert.doesNotMatch(
    visual.toLowerCase(),
    /composable capabilities/,
    'footer tagline must be gone',
  );
  assert.doesNotMatch(visual, /crv-p-tag/, 'participant badge must be gone');

  // Caller avatar and profile cards show icons.
  assert.match(
    visual,
    /crv-avatar--caller[\s\S]{0,400}?<PersonIcon/,
    'caller avatar must render an icon',
  );
  assert.match(
    visual,
    /function PersonIcon[\s\S]{0,400}?<svg/,
    'person icon must draw vector artwork',
  );
  assert.match(
    visual,
    /crv-card-icon[\s\S]{0,200}?(<PersonIcon|<BotIcon)/,
    'profile cards must render person/bot icons',
  );
});
