import { defineConfig } from "astro/config";
import starlight from "@astrojs/starlight";

const site = process.env.DOCS_SITE_URL ?? "http://localhost:4321";
const base = process.env.DOCS_BASE_PATH;

export default defineConfig({
  site,
  ...(base ? { base } : {}),
  integrations: [
    starlight({
      title: "Vxpipe",
      description:
        "An embeddable, deployable voice runtime backed by Elixir, OTP, and Membrane.",
      editLink: {
        baseUrl: "https://github.com/HashNuke/vxpipe/edit/main/docs/",
      },
      lastUpdated: true,
      social: [
        {
          icon: "github",
          label: "GitHub",
          href: "https://github.com/HashNuke/vxpipe",
        },
      ],
    }),
  ],
});
