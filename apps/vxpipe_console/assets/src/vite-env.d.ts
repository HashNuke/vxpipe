interface ImportMetaEnv {
  readonly STORYBOOK_APP_ORIGIN?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}

declare module "*.jpg" {
  const source: string;
  export default source;
}

declare module "*.png" {
  const source: string;
  export default source;
}

declare module "*.svg" {
  const source: string;
  export default source;
}
