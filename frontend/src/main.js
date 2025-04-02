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

//app.use(WagmiPlugin, { config: web3Store().wagmiAdapter.wagmiConfig });
//app.use(VueQueryPlugin, { queryClient });
// router
import router from './router';
app.use(router);

import FloatingVue from 'floating-vue';
app.use(FloatingVue);

import InfoTooltip from '@/components/InfoTooltip.vue';
app.component('InfoTooltip', InfoTooltip);

app.mount('#app');
