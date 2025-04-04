<template>
	<div class="_contacts_list" :class="{ _has_contacts: hasContacts }">
		<div class="_search mb-1" v-if="hasContacts">
			<div class="_input_search">
				<div class="_icon_search"></div>
				<input class="" type="text" v-model="search" autocomplete="off" placeholder="Search..." />

				<div class="_icon_times" v-if="search" @click="search = null"></div>
			</div>
		</div>
		<div class="_list">
			<div class="_contact" @click="select(contact.address)" v-for="contact in filteredList" :class="{ _selected: isSelected(contact.address) }">
				<Account_Item :account="contact" class="w-100" />
				<div v-if="metaRequired && contact.metaPublicKey">
					<div class="_icon_activated bg-success me-2"></div>
				</div>
			</div>
			<div class="px-2 mt-2" v-if="!metaRequired">
				<button class="btn btn-dark rounded-pill d-flex align-items-center justify-content-center p-2 w-100" @click="$mitt.emit('modal::open', { id: 'add_contact_handshake' })">
					<i class="_icon_plus bg-white"></i>
					<span class="ms-2">Add new contact</span>
				</button>
			</div>
		</div>
	</div>
</template>
<style lang="scss" scoped>
@import '@/scss/variables.scss';
@import '@/scss/breakpoints.scss';

._contacts_list {
	display: flex;
	flex-direction: column;
	overflow: hidden;

	&._has_contacts {
		flex-grow: 1;
		height: calc(100vh - 3rem);
	}

	._list {
		flex-grow: 1;
		overflow-y: auto;

		._contact {
			display: flex;
			align-items: center;
			padding: 0.5rem;
			width: 100%;
			cursor: pointer;
			border-radius: $blockRadiusSm;
			&:hover {
				background-color: lighten($black, 90%);
			}
			&._selected {
				background-color: lighten($black, 85%);
			}
		}
	}
}
</style>

<script setup>
import { ref, onMounted, watch, inject, computed, nextTick, onUnmounted } from 'vue';
import Account_Item from '@/components/Account_Item.vue';
//mport { readContract } from '@wagmi/core';
import dayjs from 'dayjs';

const $user = inject('$user');
const $web3 = inject('$web3');
const $mitt = inject('$mitt');
const $enigma = inject('$enigma');
const search = ref();

const { selected, excluded, metaRequired } = defineProps({
	selected: { type: Array, default: [] },
	excluded: { type: Array, default: [] },
	metaRequired: { type: Boolean },
});

const emit = defineEmits(['select']);

const isSelected = (address) => {
	return selected.findIndex((a) => a === address) > -1;
};

const hasContacts = computed(() => {
	return $user.contacts.filter((contact) => !contact.hidden).length > 0;
});

const select = (address) => {
	if (metaRequired && !$user.contacts.find((c) => c.address === address && c.metaPublicKey)) return;
	emit('select', address);
};

const filteredList = computed(() => {
	let list, searchTerm;
	if (!search.value) {
		list = $user.contacts;
	} else {
		searchTerm = search.value.toLowerCase();
		list = $user.contacts.filter((c) => [c.name, c.notes].some((value) => value.toLowerCase().includes(searchTerm)));
	}

	// Exclude contacts in the `excluded` list
	if (excluded?.length) {
		list = list.filter((item) => !excluded.includes(item.address)); // exclude from excluded)
	}

	//  Exclude hidden contacts
	list = list.filter((contact) => !contact.hidden);

	// Sort: Put contacts with `metaPublicKey` first
	if (metaRequired) {
		list.sort((a, b) => {
			if (a.metaPublicKey && !b.metaPublicKey) return -1; // a goes first
			if (!a.metaPublicKey && b.metaPublicKey) return 1; // b goes first
			return 0; // Keep original order otherwise
		});
	}

	const l = list.map((c) => ({
		...c,
		highlightedName: highlightText(c.name, searchTerm),
		highlightedAddress: highlightText(c.address, searchTerm),
		highlightedNotes: highlightText(c.notes, searchTerm),
	}));

	return l;
});

function highlightText(text, searchTerm) {
	if (!searchTerm) return text;
	const regex = new RegExp(`(${searchTerm})`, 'gi');
	return text.replace(regex, `<span class="_highlight_search_text">$1</span>`); // Wrap matched text with <mark>
}

onMounted(async () => {
	filteredList.value;
	if (metaRequired) checkContacts();
});

onUnmounted(async () => {});

const checkContacts = async () => {
	try {
		const contactsWithoutWetaWallet = $user.contacts.map((c) => c.address); //$user.contacts.filter((c) => !c.metaPublicKey).map((c) => c.address);
		if (!contactsWithoutWetaWallet.length) return;

		const metaPublicKeys = await $web3.registryContract.getPulicKeys(contactsWithoutWetaWallet);
		for (let i = 0; i < contactsWithoutWetaWallet.length; i++) {
			const metaPublicKey = metaPublicKeys[i];

			if (metaPublicKey && metaPublicKey.length > 2) {
				const idx = $user.contacts.findIndex((c) => c.address === contactsWithoutWetaWallet[i]);
				if (idx > -1) {
					const contactDx = $user.contactsDx.find((e) => e.id === $user.contacts[idx].id);
					if (contactDx) {
						contactDx.metaPublicKey = $enigma.encryptDataSync(metaPublicKey, $user.account.privateKey);
						contactDx.updatedAt = dayjs().valueOf();
					}
				}
			}
		}
	} catch (error) {
		console.error(error);
	}
};
</script>
