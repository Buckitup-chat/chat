import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { nodePolyfills } from 'vite-plugin-node-polyfills';
import WALC from '@lo-fi/webauthn-local-client/bundlers/vite';
import svgLoader from 'vite-svg-loader';
import fs from 'fs';
import path from 'path';
import topLevelAwait from 'vite-plugin-top-level-await';
import wasm from 'vite-plugin-wasm';
import { fileURLToPath, URL } from 'node:url';
import { ConfigPlugin } from '@dxos/config/vite-plugin';

let production = process.env.NODE_ENV === 'production';
//production = true;
//production = false;

// https://vite.dev/config/
export default defineConfig({
	esbuild: {
		supported: {
			'top-level-await': true,
		},
	},
	worker: {
		format: 'es',
		plugins: [topLevelAwait(), wasm()],
	},
	//css: {
	//	preprocessorOptions: {
	//		scss: {
	//			additionalData: `@import "bootstrap";`, // ✅ Automatically import Bootstrap
	//		},
	//	},
	//},
	plugins: [
		topLevelAwait(),
		wasm(),
		//svgLoader(),
		ConfigPlugin(),
		//{
		//  name: 'expose-sodium',
		//  configureServer() {
		//    globalThis.sodium = sodium; // Attach sodium globally
		//  },
		//  buildEnd() {
		//    globalThis.sodium = sodium; // Ensure it's available in the final build
		//  },
		//},
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
			// To exclude specific polyfills, add them to this list. Note: if include is provided, this has no effect
			//exclude: [
			//  'http', // Excludes the polyfill for `http` and `node:http`.
			//],
			// Whether to polyfill specific globals.
			globals: {
				Buffer: true, // can also be 'build', 'dev', or false
				global: true,
				process: true,
			},
			// Override the default polyfills for specific modules.
			//overrides: {
			//  // Since `fs` is not supported in browsers, we can use the `memfs` package to polyfill it.
			//  fs: 'memfs',
			//},
			// Whether to polyfill `node:` protocol imports.
			//protocolImports: true,
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
	resolve: {
		alias: {
			'@': fileURLToPath(new URL('./src', import.meta.url)),
			bootstrap: path.resolve(__dirname, 'node_modules/bootstrap'), // ✅ Fix Sass Import
		},
	},
	//resolve: {
	//  alias: {
	//    crypto: 'crypto-browserify',
	//    stream: 'stream-browserify',
	//    //assert: 'assert',
	//    //process: 'process',
	//    buffer: 'buffer',
	//    //util: 'util',
	//  },
	//},
	//optimizeDeps: {
	//  esbuildOptions: {
	//    define: {
	//      global: 'globalThis',
	//    },
	//    plugins: [
	//      NodeGlobalsPolyfillPlugin({
	//        process: true,
	//        buffer: true,
	//        //Buffer: true,
	//      }),
	//      //NodeModulesPolyfillPlugin(),
	//    ],
	//  },
	//},
	optimizeDeps: {
		esbuildOptions: {
			target: 'es2022',
		},
		exclude: ['@lo-fi/webauthn-local-client'],
	},
	build: {
		//target: 'es2022',
		//rollupOptions: {
		//  plugins: [rollupNodePolyFill()],
		//},
		//commonjsOptions: {
		//  include: ['node_modules/**/*.js']
		//},

		rollupOptions: {
			onwarn(warning, warn) {
				if (warning.message.includes('PURE') || warning.message.includes('has been externalized')) return;
				warn(warning); // Let Rollup handle other warnings normally
			},
			//plugins: [
			//  //rollupNodePolyFill(),
			//  inject({
			//    process: 'process',
			//    Buffer: ['buffer/','Buffer'],
			//  }),
			//],
		},
	},
	server: {
		https: {
			key: fs.readFileSync(path.resolve(__dirname, 'ssl/localhost-key.pem')),
			cert: fs.readFileSync(path.resolve(__dirname, 'ssl/localhost.pem')),
		},
		host: true, // Set to `true` or specify your local IP address
		//port: 5999, // Default port (change if needed)
		//open: true, // Automatically open in the default browser
	},
});
