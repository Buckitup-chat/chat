import path from "path"
import { defineConfig } from "vite"
import LV from "@lo-fi/local-vault/bundlers/vite";

import vue from "@vitejs/plugin-vue"
import liveVuePlugin from "live_vue/vitePlugin"

import { nodePolyfills } from 'vite-plugin-node-polyfills';
import topLevelAwait from 'vite-plugin-top-level-await';

import WALC from '@lo-fi/webauthn-local-client/bundlers/vite';

import fs from 'fs';

import wasm from 'vite-plugin-wasm';
import { fileURLToPath, URL } from 'node:url';
import { ConfigPlugin } from '@dxos/config/vite-plugin';

let production = process.env.NODE_ENV === 'production';

// https://vitejs.dev/config/
export default defineConfig(({ command }) => {
  const isDev = command !== "build"

  return {
    base: isDev ? undefined : "/assets",
    publicDir: "static",
    esbuild: {
      supported: {
        'top-level-await': true,
      },
    },
    worker: {
      format: 'es',
      plugins: [topLevelAwait(), wasm()],
    },
    plugins: [
      topLevelAwait(),
      wasm(),
      ConfigPlugin(),
      liveVuePlugin(),
      LV(),
      WALC(),
      nodePolyfills({
        // To add only specific polyfills, add them here. If no option is passed, adds all polyfills
        include: [
          //'assert',
          'buffer',
          'crypto',
          //'util',
          //'vm',
          'stream',
        ],
        globals: {
          Buffer: true, // can also be 'build', 'dev', or false
          global: true,
          process: true,
        },
      }),
      vue(),
    ],
    define: {
      //sodium,
      API_URL: JSON.stringify(production ? 'https://buckitupss.appdev.pp.ua/api' : 'http://localhost:3950/api'),
      IS_PRODUCTION: production,
      API_SURL: JSON.stringify(production ? 'https://buckitupss.appdev.pp.ua' : 'http://localhost:3950'), //http://192.168.100.28:3900 https://d1ca-2a01-c844-251d-5100-fa2f-930b-157d-3af1.ngrok-free.app

      API_SPATH: JSON.stringify('/api'),
      TM_BOT: JSON.stringify(production ? 'BuckitUpDemoBot' : 'BuckitUpLocalBot'),
      LIT_PKP_PUBLIC_KEY: JSON.stringify('0x040886717a89b4ca1f41c39006c85f27dad31ef1d53072bc63ba1b69e7cd70363b8e283077071af75f29c48375c98c77ae5e81995986edcd783b8fa3c45e2c1d1e'),

      IPFS_URL: JSON.stringify('https://fanaticodev.infura-ipfs.io/ipfs/'),
      INFURA_PR_ID: JSON.stringify('c683c07028924e35ae07d1b82ecbe342'),
      INFURA_SERCET: JSON.stringify('iWIYyzBCkJHfHxYlHYSKnulu3rkCP3stdSr6AX6BVsFxi4kZYPXN7Q'),
    },
    ssr: {
      // we need it, because in SSR build we want no external
      // and in dev, we want external for fast updates
      noExternal: isDev ? undefined : true,
    },
    resolve: {
      alias: {
        vue: path.resolve(__dirname, "node_modules/vue"),
        "chat": path.resolve(__dirname, "."),
        '@': fileURLToPath(new URL('./js/src', import.meta.url)),
        // '@': fileURLToPath(new URL('./../frontend/src', import.meta.url)),
        bootstrap: path.resolve(__dirname, 'node_modules/bootstrap'), // ✅ Fix Sass Import
      },
    },
    optimizeDeps: {
      // these packages are loaded as file:../deps/<name> imports
      // so they're not optimized for development by vite by default
      // we want to enable it for better DX
      // more https://vitejs.dev/guide/dep-pre-bundling#monorepos-and-linked-dependencies
      include: ["live_vue", "phoenix", "phoenix_html", "phoenix_live_view"],
      esbuildOptions: {
        // WALC (dependency) uses "top-level await", which is ES2022+
        target: "es2022",
      },
      exclude: ['@lo-fi/webauthn-local-client'],
    },
    build: {
      commonjsOptions: { transformMixedEsModules: true },
      target: "es2022",
      outDir: "../priv/static/assets", // emit assets to priv/static/assets
      emptyOutDir: true,
      sourcemap: isDev, // enable source map in dev build
      manifest: false, // do not generate manifest.json
      rollupOptions: {
        onwarn(warning, warn) {
          if (warning.message.includes('PURE') || warning.message.includes('has been externalized')) return;
          warn(warning); // Let Rollup handle other warnings normally
        },
        input: {
          app: path.resolve(__dirname, "./js/app.js"),
          main: path.resolve(__dirname, "./js/src/main.js"),
          // main: path.resolve(__dirname, "./../frontend/src/main.js"),
        },
        output: {
          // remove hashes to match phoenix way of handling assets
          entryFileNames: "[name].js",
          chunkFileNames: "[name].js",
          assetFileNames: "[name][extname]",
        },
      },
    },
    // server: {
    //   https: {
    //     key: fs.readFileSync(path.resolve(__dirname, './../frontend/ssl/localhost-key.pem')),
    //     cert: fs.readFileSync(path.resolve(__dirname, './../frontend/ssl/localhost.pem')),
    //   },
    //   host: true, // Set to `true` or specify your local IP address
    //   //port: 5999, // Default port (change if needed)
    //   //open: true, // Automatically open in the default browser
    // },
  }
})
