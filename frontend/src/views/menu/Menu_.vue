<template>
	<div class="_menu">
		<div class="_main">
			<div class="_menu_container">
				<div class="_logo_block">
					<div class="_icon_logo"></div>
				</div>

				<div class="_menu_btn order-1" :class="{ _active: menu === 'rooms' }" @click="navigateToRooms()">
					<i class="_icon_rooms" :class="{ _active: menu === 'rooms' }"></i>
					<div>Rooms</div>
				</div>

				<div class="_menu_btn order-1" :class="{ _active: menu === 'chats' }" @click="navigateToChats()">
					<i class="_icon_chats"></i>
					<div>Chats</div>
				</div>

				<div class="_menu_btn order-1" :class="{ _active: menu === 'chats' }" @click="menu = 'chats'">
					<i class="_icon_chats" :class="{ _active: menu === 'chats' }"></i>
					<div>Chats (Test)</div>
				</div>

				<div class="_menu_btn order-1" :class="{ _active: menu === 'contacts' }" @click="menu = 'contacts'">
					<i class="_icon_contacts" :class="{ _active: menu === 'contacts' }"></i>
					<div>Contacts</div>
				</div>

				<div class="_menu_btn order-1" :class="{ _active: menu === 'account' }" @click="menu = 'account'">
					<i class="_icon_profile" :class="{ _active: menu === 'account' }"></i>
					<div>Account</div>
				</div>

				<div class="_menu_btn order-1" @click="navigateToHome">
					<div class="fs-4">BE</div>
				</div>

				<div class="_menu_btn order-1" :class="{ _active: $route.path === '/storage-api-client' }"
					@click="$router.push('/storage-api-client')">
					<i class="_icon_share" :class="{ _active: $route.path === '/storage-api-client' }"></i>
					<div>storage</div>
				</div>

				<!--div class="_menu_btn order-1" :class="{ _active: menu === 'backup' }" @click="menu = 'backup'">
					<i class="_icon_share" :class="{ _active: menu === 'backup' }"></i>
					<div>Share</div>
				</div-->
			</div>
			<div class="opacity-25" v-if="!$isProd">{{ $breakpoint.current }}</div>

			<div class="_bottom_container">
				<div class="_menu_btn mb-3" @click="$mitt.emit('modal::open', { id: 'logout' })">
					<i class="_icon_logout"></i>
				</div>
			</div>
		</div>

		<div class="_sub">
			<div class="d-flex justify-content-between align-items-center p-2" v-if="menu">
				<div class="fw-bold fs-5 ms-2">{{ menuRegistry[menu].subName }}</div>

				<div class="d-flex align-items-center">
					<!--button class="btn btn-dark rounded-pill p-2 me-2" v-if="['chats', 'rooms', 'contacts', 'backup'].includes(menu)" @click="addAction()">
						<i class="_icon_plus bg-white opacity-75"></i>
					</button>

					<button class="btn btn-dark rounded-pill p-2 me-2" v-if="['account'].includes(menu)" @click="$mitt.emit('modal::open', { id: 'logout' })">
						<i class="_icon_logout bg-white opacity-75"></i>
					</button-->

					<div class="_btn_back" @click="$menuOpened = false"
						v-if="$router.options.history.state.back && $breakpoint.lt('md')">
						<i class="_icon_times"></i>
					</div>
				</div>
			</div>
			<div class="px-2" v-if="component">
				<component :is="component"></component>
			</div>
		</div>
	</div>
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
@import '@/scss/breakpoints.scss';

._account {
	display: flex;
	flex-direction: column;
	align-items: center;
	width: $sideBarWidth;
	padding-bottom: 0.5rem;
	padding-left: 0.5rem;
	padding-right: 0.5rem;
	cursor: pointer;

	._avatar {
		display: flex;
		align-items: center;
		justify-content: center;
		height: 3rem;
		width: 3rem;
		border-radius: 50%;
		overflow: hidden;
		flex-shrink: 0; // Prevents shrinking when text overflows
		margin-bottom: 0.2rem;

		img,
		svg {
			height: 100%;
			width: 100%;
			border-radius: 30rem;
			object-fit: cover;
		}
	}

	._name {
		font-weight: 500;
		font-size: 0.9rem;
		white-space: nowrap;
		overflow: hidden;
		text-overflow: ellipsis;
		max-width: 100%; // Ensures truncation works properly
		display: block; // Ensures proper alignment
	}

	&:hover {
		._name {
			color: $primary;
		}
	}
}

._menu {
	display: flex;
	width: 100%;

	@include media-breakpoint-up(sm) {
		width: unset;
	}

	._main {
		display: flex;
		flex-direction: column;
		align-items: center;
		background-color: $white;
		justify-content: space-between;
		width: 4.4rem;
		max-width: 4.4rem;

		._logo_block {
			display: flex;
			align-items: center;
			justify-content: center;
			padding: 0.8rem 0rem;

			._icon_logo {
				width: 3rem;
				height: 3rem;
			}
		}

		._menu_btn {
			display: flex;
			flex-direction: column;
			align-items: center;
			justify-content: center;
			display: flex;
			align-items: center;
			cursor: pointer;
			transition: $transition;
			font-size: 0.9rem;
			padding: 0.5rem 0.5rem;
			margin-bottom: 0.5rem;
			font-weight: 500;

			span {
				display: none;

				@include media-breakpoint-up(lg) {
					display: block;
				}
			}

			i {
				height: 1.6rem;
				width: 1.6rem;
				background-color: $black;
				transition: $transition;
			}

			&:hover {
				color: $primary;

				i {
					background-color: $primary;
				}
			}

			&._active {
				color: $primary;

				i {
					background-color: $primary;
				}
			}
		}

		._menu_container {
			display: block;
		}

		._bottom_container {
			text-align: center;
		}
	}

	._sub {
		background-color: darken($white, 5%);
		flex-grow: 1;
		display: flex;
		flex-direction: column;
		overflow: hidden;

		._menu {
			height: 100%;
			width: 100%;
		}

		._logo_block {
			display: none;
			align-items: center;
			justify-content: center;
			height: $headerHeighSm;

			@include media-breakpoint-up(md) {
				display: flex;
			}

			@include media-breakpoint-up(lg) {
				justify-content: start;
				padding: 1rem;
			}

			._icon_logo {
				width: 100%;
				height: 100%;
			}
		}

		._menu_btn {
			display: flex;
			flex-direction: column;
			align-items: center;
			justify-content: center;
			display: flex;
			align-items: center;
			font-weight: 400;
			cursor: pointer;
			transition: $transition;
			width: 5rem;

			@include media-breakpoint-up(sm) {
				padding: 0.8rem 0;
				margin-bottom: 0.5rem;
				width: unset;
			}

			span {
				display: none;

				@include media-breakpoint-up(lg) {
					display: block;
				}
			}

			i {
				height: 1.6rem;
				width: 1.6rem;
				background-color: $black;
				transition: $transition;
			}

			&:hover {
				color: $primary;

				i {
					background-color: $primary;
				}
			}

			&._active {
				font-weight: 700;
			}
		}

		._bottom_container {
			position: absolute;
			bottom: 0;
			width: 100%;
			display: none;
			text-align: center;

			@include media-breakpoint-up(sm) {
				display: block;
			}
		}

		._logout_btn {
			i {
				background-color: $dark;
			}
		}
	}
}
</style>

<script setup>
import { ref, shallowRef, onMounted, defineAsyncComponent, inject, watch, computed } from 'vue';

const $router = inject('$router');
const $route = inject('$route');

const $mitt = inject('$mitt');
const $breakpoint = inject('$breakpoint');
const $menuOpened = inject('$menuOpened');
const menu = ref();
const component = shallowRef(null);
const menuRegistry = {
	contacts: {
		component: 'Menu_Contacts',
		subName: 'My Contacts',
	},
	rooms: {
		component: 'Menu_Rooms',
		subName: 'Rooms',
	},
	chats: {
		component: 'Menu_Chats',
		subName: 'Chats',
	},
	account: {
		component: 'Menu_Account',
		subName: 'My account',
	},
};

onMounted(async () => {
	if (menu.value) {
		const registry = menuRegistry[menu.value];
		component.value = await defineAsyncComponent(() => import(`./views/${registry.component}.vue`));
	}
});

const navigateToHome = () => {
	// Change the browser location to `/` and reload the page
	window.location.href = '/';
};

const navigateToRooms = () => {
	window.location.href = 'https://buckitup.xyz/rooms';
};

const navigateToChats = () => {
	window.location.href = 'https://buckitup.xyz/chats';
};

watch(
	() => menu.value,
	async (newVal) => {
		if (newVal) {
			const registry = menuRegistry[newVal];
			component.value = await defineAsyncComponent(() => import(`./views/${registry.component}.vue`));
		}
	},
);

watch(
	() => $route.name,
	(newVal) => {
		if (newVal) {
			if ($route.name.includes('contact')) menu.value = 'contacts';
			if ($route.name.includes('room')) menu.value = 'rooms';
			if ($route.name.includes('chat')) menu.value = 'chats';
			if ($route.name.includes('account') || $route.name.includes('backup')) menu.value = 'account';
			if ($route.name === 'storage_api_client') menu.value = null;
		}
	},
);
</script>
