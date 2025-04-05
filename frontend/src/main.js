import { createApp } from 'vue';

import App from './App.vue';

//
import 'bootstrap';
import './scss/app.scss';

import { web3Store } from './store/web3.store.js';
import { userStore } from './store/user.store.js';
import { createPinia } from 'pinia';
import $socket from './libs/socket';
import $mitt from './libs/emitter';
import { useLoader } from './store/loader.store.js';
import $swal from './libs/swal';

// dayjs
import dayjs from 'dayjs';
import relativeTime from 'dayjs/plugin/relativeTime';
dayjs.locale('en');
dayjs.extend(relativeTime);

// libs
import globalFilters from './libs/filters';
import * as $enigma from './libs/enigma';
import { EncryptionManager } from './libs/EncryptionManager';

const app = createApp(App);

const pinia = createPinia();

// Pinia
app.use(pinia);

// breakpoint
import { useBreakpoint } from './store/breakpoint.store';
app.config.globalProperties.$breakpoint = useBreakpoint();
app.config.globalProperties.$breakpoint.init();
app.provide('$breakpoint', useBreakpoint());

// mitt
app.provide('$mitt', $mitt);
app.config.globalProperties.$mitt = $mitt;

app.config.globalProperties.$date = dayjs;
app.provide('$date', dayjs);

const $isProd = !location.origin.includes('localhost') && !location.origin.includes('192');
app.provide('$isProd', $isProd);
app.config.globalProperties.$isProd = $isProd;

app.config.globalProperties.$filters = globalFilters;
app.config.globalProperties.$location = window.location;

app.provide('$socket', $socket);

// web3Store
app.config.globalProperties.$web3 = web3Store();
app.provide('$web3', web3Store());

app.config.globalProperties.$user = userStore();
app.provide('$user', userStore());

app.config.globalProperties.$loader = useLoader();
app.provide('$loader', useLoader());

app.provide('$enigma', $enigma);
app.provide('$encryptionManager', new EncryptionManager(IS_PRODUCTION));

app.config.globalProperties.$swal = $swal;
app.provide('$swal', $swal);

// router
import router from './router';
app.use(router);

import FloatingVue from 'floating-vue';
app.use(FloatingVue);

import InfoTooltip from '@/components/InfoTooltip.vue';
app.component('InfoTooltip', InfoTooltip);

// check only one tab started
const channel = new BroadcastChannel('buckitup-app');
let blocked = false;
channel.onmessage = (e) => {
	if (e.data === 'app-already-running') {
		blocked = true;
		window.stop();
		document.body.innerHTML = '<h4 class="text-white text-center mt-5">App is already open in another tab.</h4>';
	}
};
channel.postMessage('ping');
setTimeout(() => {
	// Wait a bit for any responses from other tabs
	if (!blocked) {
		channel.postMessage('app-already-running'); // If no response, mark this as the main tab
	}
}, 100); // can increase to 300ms if needed

app.mount('#app');
