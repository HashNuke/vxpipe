import { defineCollection } from 'astro:content';
import { z } from 'astro/zod';

import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';
import { ExtendDocsSchema } from 'starlight-theme-black/schema';

export const collections = {
  docs: defineCollection({
    loader: docsLoader(),
    schema: docsSchema({
      // The theme's schema defaults the hero to its centered layout; without it
      // the theme falls back to the side-by-side media-left layout.
      extend: ExtendDocsSchema.extend({
        // Release tag whose compose.yml the quickstart runs, for example v0.1.0.
        release: z.string().regex(/^v\d+\.\d+\.\d+$/).optional(),
      }),
    }),
  }),
};
