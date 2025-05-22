<template>
	<div class="wrapper" v-if="$user.account">
		<Menu class="_menu" :class="{ _opened: $menuOpened }" />
		<div class="_menu_backdrop" :class="{ _opened: $menuOpened && $breakpoint.lt('md') }" @click="$menuOpened = false"></div>

		<div class="_main" v-if="$user.account">
			<router-view v-slot="{ Component, route }">
				<component :is="Component" :key="route.path" />
			</router-view>
		</div>
	</div>

	<div v-if="!$user.account" class="_login">
		<router-view v-slot="{ Component, route }">
			<component :is="Component" :key="route.path" />
		</router-view>
	</div>

	<Modal ref="$modal" />
	<Swal ref="$swalModal" />
	<Loader />
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
@import '@/scss/breakpoints.scss';

._login {
	width: 100vw; /* full browser width */
	display: flex; /* use Flexbox */
	justify-content: center; /* horizontally center items */
	align-items: center; /* vertically center items */
}

.wrapper {
	display: flex;
	height: 100vh; // Full viewport height
	flex-direction: row;
}

._menu {
	z-index: 10;
	white-space: nowrap;
	height: 100%;
	flex-shrink: 0;
	position: fixed;
	top: 0;
	left: 0;
	width: 0;
	transition: $transition;
	&._opened {
		width: 360px;
		max-width: 360px;
	}
	@include media-breakpoint-up(md) {
		position: unset;
		width: 360px;
		max-width: 360px;
	}
	box-shadow: 15px 0rem 1rem 0px rgb(0 0 0 / 12%);
	overflow: hidden;
}
._menu_backdrop {
	position: fixed;
	height: 100%;
	width: 0;
	z-index: 9;
	background-color: rgba(0, 0, 0, 0.3);
	//transition: backdrop-filter .3s ease;
	pointer-events: none;
	&._opened {
		width: 100%;
		pointer-events: all;
		cursor: pointer;
		//backdrop-filter: blur(3px); // Apply blur effect
		//-webkit-backdrop-filter: blur(3px); // For Safari support
	}
}
/* 📌 Main Section */
._main {
	display: flex;
	flex-direction: row;
	overflow: hidden;
	height: 100%;
	width: 100%;
}

/* 📌 Mobile: Move `_menu` to Bottom */
@include media-breakpoint-up(md) {
	.wrapper {
		flex-direction: row;
	}

	._main {
		flex-grow: 1; // Takes remaining space
		height: 100%; // Adjust height to fit bottom menu
	}
}
</style>

<script setup>
import Loader from './components/Loader.vue';
import Menu from '@/views/menu/Menu_.vue';
import Modal from '@/components/modal/Modal_.vue';
import Swal from '@/components/swal/Swal_.vue';
import { ref, provide, watch, onMounted, inject, computed, nextTick } from 'vue';
import { useRoute, useRouter } from 'vue-router';

const $socket = inject('$socket');
const $mitt = inject('$mitt');
const $user = inject('$user');
const $breakpoint = inject('$breakpoint');
const $encryptionManager = inject('$encryptionManager');
const $web3 = inject('$web3');
const $swal = inject('$swal');
const $loader = inject('$loader');
const $isProd = inject('$isProd');

const $appstate = ref({});
provide('$appstate', $appstate);

const $route = useRoute();
provide('$route', $route);

const $router = useRouter();
provide('$router', $router);

const $menuOpened = ref();
provide('$menuOpened', $menuOpened);

const $modal = ref();
provide('$modal', $modal);

const $swalModal = ref();
provide('$swalModal', $swalModal);

const timestamp = ref();
provide('$timestamp', timestamp);

watch(
	() => $breakpoint.current,
	() => {
		if ($breakpoint.gt('sx')) $menuOpened.value = true;
	},
);

onMounted(async () => {
	$user.setEncryptionManager($encryptionManager);

	window.addEventListener('online', () => ($user.isOnline = navigator.onLine));
	window.addEventListener('offline', () => ($user.isOnline = navigator.onLine));
	setTimeout(function tick() {
		timestamp.value = Math.floor(Date.now().valueOf() / 1000);
		setTimeout(tick, 1000);
	}, 1000);

	$user.vaults = await $encryptionManager.getVaults();
});
</script>
