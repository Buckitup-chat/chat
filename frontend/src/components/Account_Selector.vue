<template>
	<div>
		<div class="_contacts_list mb-2" v-if="$user.vaults.length">
			<div class="_search" v-if="$user.vaults.length > 5">
				<div class="_input_search">
					<div class="_icon_search"></div>
					<input class="" type="text" v-model="search" autocomplete="off" placeholder="Search..." />
					<div class="_icon_times" v-if="search" @click="search = null"></div>
				</div>
			</div>
			<div class="_list">
				<div
					class="_contact"
					@click="select(account)"
					v-for="account in filteredList"
					:class="{ _selected: account.publicKey === selected?.publicKey, _connected: account.publicKey === $user.account?.publicKey }"
				>
					<Account_Item :account="account" />
				</div>
			</div>
		</div>

		<div class="d-flex w-100" v-if="selected">
			<button type="button" class="btn btn-dark d-flex justify-content-center align-items-center w-100" v-if="selected.publicKey === $user.account?.publicKey" @click="logout()">
				<i class="_icon_signout bg-white me-2"></i> Logout
			</button>

			<!--button type="button" class="btn btn-dark d-flex justify-content-center align-items-center w-100" v-if="selected.publicKey !== $user.account?.publicKey" @click="signin()">
				<i class="_icon_signin bg-white me-2"></i> Sign in
			</button-->

			<button
				type="button"
				class="btn btn-dark d-flex justify-content-center align-items-center ms-1"
				@click="$mitt.emit('modal::open', { id: 'account_backup' })"
				v-if="selected.publicKey === $user.account?.publicKey"
				v-tooltip="'Backup account data'"
			>
				<i class="_icon_backups bg-white px-2"></i>
			</button>

			<button type="button" class="btn btn-dark d-flex justify-content-center align-items-center ms-1" @click="deleteAccount()" v-tooltip="'Wipe account data from this device'">
				<i class="_icon_delete bg-white px-2"></i>
			</button>
		</div>
	</div>
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
@import '@/scss/breakpoints.scss';

._contacts_list {
	max-height: 30rem; // calc(100vh - 3rem);
	display: flex;
	flex-direction: column;
	overflow: hidden;
	._list {
		flex-grow: 1;
		overflow-y: auto;
		max-height: 14rem;
		._contact {
			display: flex;
			align-items: center;
			padding: 0.5rem;
			width: 100%;
			cursor: pointer;
			border-radius: $blockRadiusSm;
			margin-bottom: 0.3rem;
			&:hover {
				background-color: lighten($black, 90%);
			}
			&._selected {
				background-color: lighten($black, 85%);
			}
			&._connected {
				border: 1px solid lighten($black, 50%);
			}
		}
	}
}
._action_btn {
	padding: 1.2rem;
	margin-left: 0.3rem;
	margin-right: 0.3rem;
	i {
		height: 1.5rem;
		width: 1.5rem;
	}
}
</style>

<script setup>
import { computed, inject, ref, onMounted, nextTick } from 'vue';
import Account_Item from '@/components/Account_Item.vue';

const $mitt = inject('$mitt');
const $loader = inject('$loader');
const $web3 = inject('$web3');
const $user = inject('$user');
const $swal = inject('$swal');
const $router = inject('$router');
const $route = inject('$route');
const $swalModal = inject('$swalModal');
const $isProd = inject('$isProd');
const $encryptionManager = inject('$encryptionManager');
const selected = ref();
const search = ref();

onMounted(async () => {
	$user.vaults = await $encryptionManager.getVaults();
	selected.value = $user.account;
});

const select = (account) => {
	reset();
	selected.value = account;
	signin();
};

const reset = () => {
	selected.value = null;
};

const filteredList = computed(() => {
	function highlightText(text, searchTerm) {
		if (!searchTerm || !text) return text;
		const regex = new RegExp(`(${searchTerm})`, 'gi');
		return text.replace(regex, `<span class="_highlight_search_text">$1</span>`); // Wrap matched text with <mark>
	}

	let list, searchTerm;
	if (!search.value) {
		list = $user.vaults;
	} else {
		searchTerm = search.value.toLowerCase();
		list = $user.vaults.filter((c) =>
			[c.name, c.notes].some(
				(
					value, //, c.address
				) => value && value.toLowerCase().includes(searchTerm),
			),
		);
	}

	if ($user.account?.address) {
		list = list.slice().sort((a, b) => {
			if (a.address === $user.account.address) return -1;
			if (b.address === $user.account.address) return 1;
			return 0;
		});
	}

	return list.map((c) => ({
		...c,
		highlightedName: highlightText(c.name, searchTerm),
		highlightedAddress: highlightText(c.address, searchTerm),
		highlightedNotes: highlightText(c.notes, searchTerm),
	}));
});

const signin = async () => {
	$loader.show();

	let swalInstance;
	try {
		const nextUser = JSON.parse(JSON.stringify(selected.value));
		await $user.logout();

		reset();

		if ($route.name !== 'login') {
			$router.push({ name: 'login' });
			$mitt.emit('modal::close');
		}

		if ($isProd) {
			swalInstance = $swal.fire({
				icon: 'info',
				title: 'Authenticate with PassKey',
				footer: 'Please confirn PassKey on your device when it prompts',
				timer: 3000,
			});
		}

		await $encryptionManager.connectToVault(nextUser.vaultId);

		if (swalInstance) swalInstance.close();

		if (!$encryptionManager.isAuth) {
			$loader.hide();
			return;
		}
		$user.account = await $user.fromVaultFormat(await $encryptionManager.getData());

		if ($user.account.spaceId) {
			const spaces = $user.dxClient.spaces.get();
			const space = spaces.find((s) => s.id === $user.account.spaceId);

			if (space) {
				$user.space = space;
				console.log('Space reused', space.id);
			} else {
				console.log('Space not found');
			}
		}
		if (!$user.space) {
			await $user.createSpace();
		}

		await $user.openSpace(nextUser);

		await $user.checkMetaWallet();

		nextTick(() => {
			try {
				$router.replace({ name: 'account_info' });
			} catch (error) {
				console.log('signin', error);
			}
		});

		$mitt.emit('modal::close');
	} catch (error) {
		console.error('signin', error);
	}
	$loader.hide();
};

const deleteAccount = async () => {
	if (!(await $swalModal.value.open({ id: 'delete_account' }))) return;
	if ($user.account?.address === selected.value.address) {
		$user.logout();
		$router.push({ name: 'login' });
		$mitt.emit('modal::close');
	}
	const idx = $user.vaults.findIndex((v) => v.address === selected.value.address);
	if (idx > -1) $user.vaults.splice(idx, 1);

	reset();
};

const logout = async () => {
	await signout();
	$mitt.emit('modal::close');
};

const signout = async () => {
	await $user.logout();
	reset();
	if ($route.name !== 'login') {
		$router.push({ name: 'login' });
	}
};
</script>
