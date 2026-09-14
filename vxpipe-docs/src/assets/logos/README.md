# Logos

Use `@lobehub/icons` for logos available in LobeHub. Astro's React integration
renders these components into static markup; omit `client:*` directives.
Import the specific icon component (for example,
`@lobehub/icons/es/Gemini/components/Mono.js`) to load only the required variant.

Keep fallback logos that LobeHub does not have directly in this directory.
Use lowercase, hyphenated filenames and prefer SVGs.
Record new asset sources below. Storing a logo here does not imply that VxPipe
supports the provider; pages explicitly choose which logos to display.

These SVG assets are bundled locally and inherit the page's text color for
Starlight's light and dark themes.

- [Deepgram](https://github.com/simple-icons/simple-icons/blob/develop/icons/deepgram.svg): Simple Icons.
- [Twilio](https://github.com/simple-icons/simple-icons/blob/13.0.0/icons/twilio.svg): Simple Icons 13.0.0.
- [Telnyx wordmark](https://dila2qpfw3s64.cloudfront.net/_next/static/media/telnyx-logo-text.3ol7qfk480jrf.svg): Telnyx website header.

Simple Icons is distributed under [CC0](https://github.com/simple-icons/simple-icons/blob/develop/LICENSE.md). Brand marks remain the property of their respective owners.
