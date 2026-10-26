# Built-in service favicons

Bundled favicons keep built-in integrations identifiable when the hosted directory
is unavailable. Sources were inspected on 2026-10-25. Use a scalable SVG when the
landing page declares one; otherwise use its largest declared raster icon, including
apple-touch icons and icons in a web manifest linked from that HTML. Files retain
their original bytes; no wordmarks, social images, or icon-library substitutes.

| Service | Landing page | Bundled file | Format / source declaration |
| --- | --- | --- | --- |
| Deepgram | [https://deepgram.com/](https://deepgram.com/) | [deepgram.ico](deepgram.ico) | [ICO, largest frame 64 × 64](https://deepgram.com/favicon.ico?93834efdfdd5438d) |
| Rime | [https://www.rime.ai/](https://www.rime.ai/) | [rime.png](rime.png) | [PNG, 512 × 512](https://cdn.prod.website-files.com/6a4d70b04f64b0fe572eff71/6a554ed17f2b9d0f80597943_rime_LinkedIn_profile.png) |
| Cartesia | [https://www.cartesia.ai/](https://www.cartesia.ai/) | [cartesia.svg](cartesia.svg) | [SVG](https://www.cartesia.ai/favicon.svg) |
| ElevenLabs | [https://elevenlabs.io/](https://elevenlabs.io/) | [elevenlabs.svg](elevenlabs.svg) | [SVG](https://elevenlabs.io/icon.svg?c23f5371fdd26632) |
| Google AI Studio | [https://aistudio.google.com/](https://aistudio.google.com/) | [google-ai-studio.png](google-ai-studio.png) | [PNG, 512 × 512](https://www.gstatic.com/images/branding/productlogos/ai_studio/v1/web-512dp/logo_ai_studio_color_1x_web_512dp.png) |
| Zenmux | [https://zenmux.ai/](https://zenmux.ai/) | [zenmux.svg](zenmux.svg) | [SVG (light favicon)](https://cdn.marmot-cloud.com/storage/tbox-router/2025/08/18/mplTJpZ/big-logo.svg) |
| DeepSeek | [https://www.deepseek.com/](https://www.deepseek.com/) | [deepseek.ico](deepseek.ico) | [ICO, 225 × 225](https://www.deepseek.com/favicon.ico) |
| OpenRouter | [https://openrouter.ai/](https://openrouter.ai/) | [openrouter.png](openrouter.png) | [PNG, 512 × 512 (linked web manifest)](https://openrouter.ai/icon-pwa-512.png) |
| Fireworks AI | [https://fireworks.ai/](https://fireworks.ai/) | [fireworks.svg](fireworks.svg) | [SVG](https://fireworks.ai/icon.svg?26fd47f5c5eddcac) |
| Telnyx | [https://telnyx.com/](https://telnyx.com/) | [telnyx.png](telnyx.png) | [PNG, 750 × 750](https://telnyx.com/favicon.ico) |
| Twilio | [https://www.twilio.com/](https://www.twilio.com/) | [twilio.png](twilio.png) | [PNG, 512 × 512 (linked web manifest)](https://www.twilio.com/content/dam/twilio-com/core-assets/social/android-chrome-512x512.png) |
| OpenAI | [OpenAI](https://openai.com/) | [openai.svg](openai.svg) | [SVG, rel=icon](https://openai.com/favicon.svg) |
| Vertex AI (legacy inventory) | [Google Cloud Vertex AI](https://cloud.google.com/vertex-ai) | [vertex-ai.png](vertex-ai.png) | [PNG, 192 × 192, apple-touch icon](https://www.gstatic.com/cgc/super_cloud_gradient.png) |

The Google asset is specifically AI Studio's 512px favicon, not the general
Google G mark. Telnyx serves PNG bytes at a `.ico` URL; the local filename uses
`.png` to reflect the actual format. Rime's file has a profile-image filename,
but its landing page explicitly declares it as a 512px `rel="icon"` favicon.

MorseCode API's [homepage](https://morsecode.vxpipe.com/) has no favicon declaration.
It uses the shared neutral Plug placeholder, as requested. The same placeholder
handles image loading failures, without service initials or fabricated branding.

OpenAI declares `/favicon.svg`, a 48px ICO, and a 180px Apple icon on its homepage.
The user supplied a browser download of the SVG after headless requests received
Cloudflare verification. It is bundled byte-for-byte, including its light/dark
color-scheme support.

These assets identify their respective services. Trademarks remain the property
of their owners; bundling them does not imply endorsement or change their license.
