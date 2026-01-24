import { defineConfig } from 'vite';
import vue from '@vitejs/plugin-vue';
import { nodePolyfills } from 'vite-plugin-node-polyfills';
import topLevelAwait from 'vite-plugin-top-level-await';

import WALC from '@lo-fi/webauthn-local-client/bundlers/vite';

import fs from 'fs';
import path from 'path';

import wasm from 'vite-plugin-wasm';
import { fileURLToPath, URL } from 'node:url';

let production = process.env.NODE_ENV === 'production';
let productionApi = process.env.NODE_ENV === 'production';
production = true;
//production = false;
productionApi = true;

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
	plugins: [
		topLevelAwait(),
		wasm(),
		WALC(),
		nodePolyfills({
			// To add only specific polyfills, add them here. If no option is passed, adds all polyfills
			include: [
				//'assert',
				'buffer',
				'crypto',
				//'util',
				//'vm',
				// 'stream',
				// 'stream-browserify'
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
		CONNECTOR_URL: JSON.stringify(productionApi ? 'wss://buckitupss.appdev.pp.ua/connector' : 'ws://localhost:3953'),
		IS_PRODUCTION: production,
		IS_PRODUCTION_API: productionApi,
		API_SURL: JSON.stringify(productionApi ? 'https://buckitupss.appdev.pp.ua' : 'http://localhost:3950'), //http://192.168.100.28:3900 https://d1ca-2a01-c844-251d-5100-fa2f-930b-157d-3af1.ngrok-free.app

		API_SPATH: JSON.stringify('/api'),
		TM_BOT: JSON.stringify(productionApi ? 'BuckitUpDemoBot' : 'BuckitUpLocalBot'),
		LIT_PKP_PUBLIC_KEY: JSON.stringify('0x040886717a89b4ca1f41c39006c85f27dad31ef1d53072bc63ba1b69e7cd70363b8e283077071af75f29c48375c98c77ae5e81995986edcd783b8fa3c45e2c1d1e'),

		IPFS_URL: JSON.stringify('https://fanaticodev.infura-ipfs.io/ipfs/'),
		INFURA_PR_ID: JSON.stringify('c683c07028924e35ae07d1b82ecbe342'),
		INFURA_SERCET: JSON.stringify('iWIYyzBCkJHfHxYlHYSKnulu3rkCP3stdSr6AX6BVsFxi4kZYPXN7Q'),
	},
	resolve: {
		alias: {
			'@': fileURLToPath(new URL('./src', import.meta.url)),
			bootstrap: path.resolve(__dirname, 'node_modules/bootstrap'), // ✅ Fix Sass Import
			// '@noble/hashes/hmac': '@noble/hashes/hmac.js',
			// '@noble/hashes/sha256': '@noble/hashes/sha256.js',
			// '@noble/hashes/sha512': '@noble/hashes/sha512.js',
			// '@noble/hashes/utils': '@noble/hashes/utils.js',

			// 'stream/promises': require.resolve('./src/polyfills/stream-promises.js'),
		},
	},
	optimizeDeps: {
		esbuildOptions: {
			target: 'es2022',
		},
		exclude: [
			'@lo-fi/webauthn-local-client',
			'@electric-sql/pglite',
			'@electric-sql/pglite/worker',
			'@noble/hashes',
			'@noble/hashes/hmac',
			'@noble/hashes/sha256',
			// 'stream',
			// 'stream/promises'
		],
	},
	server: {
		proxy: {
			'/api': {
				target: 'https://buckitup.xyz',
				changeOrigin: true,
				rewrite: (path) => path.replace(/^\/api/, ''),
				// secure: false,
			},
		},
	},
	base: '/frontend',
	build: {
		outDir: "../priv/static/frontend", // emit assets to priv/static/frontend
		emptyOutDir: true,
		// disable source maps & size reports to save memory
		sourcemap: false,
		reportCompressedSize: false,
		minify: 'esbuild',
		cssCodeSplit: false,
		rollupOptions: {
			onwarn(warning, warn) {
				if (warning.message.includes('PURE') || warning.message.includes('has been externalized')) return;
				warn(warning); // Let Rollup handle other warnings normally
			},
			maxParallelFileOps: 10
		},
	},
	// server: {
	// 	https: {
	// 		key: fs.readFileSync(path.resolve(__dirname, '../ssl/localhost-key.pem')),
	// 		cert: fs.readFileSync(path.resolve(__dirname, '../ssl/localhost.pem')),
	// 	},
	// 	host: true, // Set to `true` or specify your local IP address
	// 	//port: 5999, // Default port (change if needed)
	// 	//open: true, // Automatically open in the default browser
	// },
});
