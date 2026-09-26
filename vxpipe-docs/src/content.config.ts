import { defineCollection } from 'astro:content';
import { z } from 'astro/zod';

import { docsLoader } from '@astrojs/starlight/loaders';
import { docsSchema } from '@astrojs/starlight/schema';

export const collections = {
  docs: defineCollection({
    loader: docsLoader(),
    schema: docsSchema({
      extend: z.object({
        // Release tag whose compose.yml the quickstart runs, for example v0.1.0.
        release: z.string().regex(/^v\d+\.\d+\.\d+$/).optional(),
      }),
    }),
  }),
};
