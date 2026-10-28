/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_APP_TITLE?: string;
  readonly VITE_APP_ENV?: string;
  readonly VITE_APP_BASE_API?: string;
  readonly VITE_APP_BASE_AI?: string;
  readonly VITE_APP_FLOW_API?: string;
  readonly VITE_APP_AUTH_TYPE?: string;
  readonly VITE_APP_CLIENTID?: string;
  readonly VITE_APP_SERVER_URL?: string;
  readonly VITE_APP_THIS_APP_URL?: string;
  readonly VITE_APP_WEBSOCKET_API?: string;
  readonly VITE_APP_OPEN_PROXY_PUT_DELETE_REQUEST?: string;
  readonly VITE_RP_VIEW_URL?: string;
  readonly VITE_APP_AES_KEY?: string;

  readonly VITE_GLOB_API_URL?: string;
  readonly VITE_GLOB_API_URL_PREFIX?: string;

  readonly VITE_LLM_GATEWAY_MODE?: string;
  readonly VITE_LLM_GATEWAY_URL?: string;
  readonly VITE_LLM_GATEWAY_TOKEN?: string;

  readonly VITE_HARNESS_APP_NAME?: string;
  readonly VITE_HARNESS_LOGO?: string;
  readonly VITE_HARNESS_URL?: string;

  readonly VITE_IDEA_URL?: string;
  readonly VITE_IDEA_TOKEN?: string;

  readonly VITE_TERMINAL_URL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}

declare module '*.vue' {
  import type { DefineComponent } from 'vue';

  const component: DefineComponent<Record<string, unknown>, Record<string, unknown>, any>;
  export default component;
}
