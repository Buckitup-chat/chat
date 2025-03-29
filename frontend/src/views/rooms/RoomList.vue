<template>
	<div class="_contacts_list" :class="{ _has_contacts: $user.account?.chats?.length }">
		<div class="_search" v-if="$user.account?.chats?.length">
			<div class="_input_search">
				<div class="_icon_search"></div>
				<input class="" type="text" v-model="search" autocomplete="off" placeholder="Search..." />

				<div class="_icon_times" v-if="search" @click="search = null"></div>
			</div>
		</div>

		<div class="_list" v-if="$user.account?.chats?.length"></div>

		<!--a href="#" @click.prevent="addContact()">
            Add contact
        </a-->
	</div>
</template>
<style lang="scss" scoped>
@import '@/scss/variables.scss';
@import '@/scss/breakpoints.scss';

._contacts_list {
	//width: 100%;
	//height: 100%;

	display: flex;
	flex-direction: column;

	/* Allows wrapper to take full height */
	overflow: hidden;
	/* Prevents content from breaking layout */
	padding: 0.3rem;

	&._has_contacts {
		flex-grow: 1;
	}

	._search {
		flex-shrink: 0;
		//position: absolute;
		//top: 0;
		//left: 0;
		//padding: .5rem;
		//width: 100%;

		._input_search {
			width: 100%;
			display: flex;
			justify-content: start;
			align-items: center;
			padding: 0.2rem 0.2rem 0.2rem 0.2rem;
			background-color: $white;
			border: 1px solid $light_grey2;
			transition: all 0.3s ease;
			border-radius: $blockRadius;

			margin-bottom: 0.5rem;

			&:placeholder {
				color: $grey_dark;
				font-weight: 300;
			}

			input {
				background-color: transparent;
				border: none;
				color: $black;
				width: 100%;
			}

			&:focus-within {
				border: 1px solid $light_grey2;
			}

			div {
				padding-left: 1rem;
				padding-right: 1rem;
				background-color: $grey_dark;
				height: 1rem;
				width: 1rem;

				&._icon_times {
					cursor: pointer;
				}

				transition: all 0.3s ease;

				&:hover {
					&._icon_times {
						background-color: $dark;
					}
				}
			}
		}
	}

	._list {
		flex-grow: 1;
		/* `c` takes remaining space */
		overflow-y: auto;
		/* Makes `c` scrollable if content overflows */
	}
}
</style>

<style lang="scss">
@import '@/scss/variables.scss';

._highlight_search_text {
	color: $primary; // Deep orange text color
	font-weight: bold;
}
</style>
<script setup>
import { ref, onMounted, watch, inject, computed, nextTick, onUnmounted } from 'vue';
import { ethers, utils, Wallet } from 'ethers';

const $user = inject('$user');
const $timestamp = inject('$timestamp');
const $web3 = inject('$web3');
const $swal = inject('$swal');
const $socket = inject('$socket');
const $loader = inject('$loader');
const $modal = inject('$modal');
const $enigma = inject('$enigma');
const $encryptionManager = inject('$encryptionManager');

const search = ref();

const filteredList = computed(() => {
	let list, searchTerm;
	if (!search.value) {
		list = $user.contacts;
	} else {
		searchTerm = search.value.toLowerCase();

		list = $user.contacts.filter((c) =>
			[c.name, c.notes].some(
				(
					value, //, c.address
				) => value.toLowerCase().includes(searchTerm),
			),
		);
	}
	return list.map((c) => ({
		...c,
		highlightedName: highlightText(c.name, searchTerm),
		highlightedAddress: highlightText(c.address, searchTerm),
		highlightedNotes: highlightText(c.notes, searchTerm),
	}));
});

function highlightText(text, searchTerm) {
	if (!searchTerm) return text;
	const regex = new RegExp(`(${searchTerm})`, 'gi');
	return text.replace(regex, `<span class="_highlight_search_text">$1</span>`); // Wrap matched text with <mark>
}

onMounted(async () => {
	//test()
});

onUnmounted(async () => {});

const addContact = async () => {
	try {
		// Get all media devices
		const devices = await navigator.mediaDevices.enumerateDevices();
		// Check if there is at least one video input (camera)
		hasCamera.value = devices.some((device) => device.kind === 'videoinput');
	} catch (error) {
		console.error('Error checking camera availability:', error);
	}

	if (!hasCamera.value) {
		$swal.fire({
			icon: 'error',
			title: 'Camera not available on this device',
			timer: 30000,
		});
		return;
	}
	console.log($modal);
	$modal.value.open({ id: 'handshake' });
};
</script>
