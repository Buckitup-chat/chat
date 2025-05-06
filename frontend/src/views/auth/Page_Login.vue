<template>
	<div class="d-flex flex-column justify-content-center align-items-center _block px-2 pt-5" v-if="!$user.account">
		<div class="_icon_logo bg-white"></div>

		<div class="px-3 w-100 mb-3" v-if="$user.vaults.length && mode !== 'existing'">
			<button class="btn btn-outline-light w-100" @click="setMode('existing')">Connect existing account</button>
		</div>

		<div class="_input_block mb-3 w-100" v-if="$user.vaults.length && mode === 'existing'">
			<div class="fs-4 text-center mb-2">Connect existing account</div>
			<Account_Selector />
		</div>

		<div class="px-3 w-100 mb-3">
			<button class="btn btn-outline-light w-100" @click="setMode('create')">Create new account</button>
		</div>

		<div class="px-3 w-100 mb-3">
			<button class="btn btn-outline-light w-100" @click="setMode('restore')">Import from local backup</button>
		</div>

		<div class="px-3 w-100 mb-3">
			<button class="btn btn-outline-light w-100" @click="setMode('shares')">Restore from shares</button>
		</div>

		<div class="px-3 w-100 mb-3">
			<button class="btn btn-outline-light w-100" @click="setMode('dxos_connect')">Sync with other device</button>
		</div>

		<div class="px-3 w-100 mb-3 opacity-50">
			<button class="btn btn-outline-light w-100" @click="wipe()">Wipe all</button>
		</div>
		<div class="px-3 w-100 mb-3 opacity-50">
			<button class="btn btn-outline-light w-100" @click="connectVaultLocalApp()">Local app connect</button>
		</div>
	</div>
</template>

<style lang="scss" scoped>
._block {
	width: 100%;
	max-width: 23rem;
	height: 100%;
	._icon_logo {
		min-height: 6rem;
		min-width: 6rem;
		margin-bottom: 2rem;
	}
}
</style>

<script setup>
import Account_Selector from '@/components/Account_Selector.vue';
import { inject, ref, onMounted, onUnmounted } from 'vue';
import * as $enigma from '@/libs/enigma';

const $mitt = inject('$mitt');
const $user = inject('$user');
const $route = inject('$route');
const $encryptionManager = inject('$encryptionManager');
const mode = ref();

onMounted(async () => {
	await updateData();

	if ($route.query.encryptionKey) {
		mode.value = 'dxos_connect';
		$mitt.emit('modal::open', { id: 'account_dxos_connect' });
	} else if ($user.vaults.length) {
		mode.value = 'existing';
	}

	$mitt.on('account::created', updateData);
});

onUnmounted(async () => {
	$mitt.off('account::created', updateData);
});

const updateData = async () => {
	$user.vaults = await $encryptionManager.getVaults();
};

const wipe = async () => {
	await $user.clearIndexedDB();
	location.reload();
};

function setMode(m) {
	mode.value = m;
	if (m === 'create') $mitt.emit('modal::open', { id: 'account_create' });
	if (m === 'restore') $mitt.emit('modal::open', { id: 'account_restore_local' });
	if (m === 'shares') $mitt.emit('modal::open', { id: 'account_restore_shares' });
	if (m === 'dxos_connect') $mitt.emit('modal::open', { id: 'account_dxos_connect' });
}

const connectVaultLocalApp = async () => {
	const vaults = await $encryptionManager.getVaults();
	if (!vaults?.length) return;
	let currentUser = vaults.find((u) => u.current);
	if (!currentUser) currentUser = vaults[0];

	await $encryptionManager.connectToVault(currentUser.vaultId);
	if (!$encryptionManager.isAuth) return;

	const vault = await $encryptionManager.getData();
	const privateKeyB64 = $enigma.stringToBase64($enigma.hexToUint8Array(vault.privateKey.slice(2)));
	const publicKeyB64 = $enigma.stringToBase64($enigma.getPublicKeyFromPrivateKey(vault.privateKey.slice(2)));

	const resp = [[currentUser.name, $enigma.combineKeypair(privateKeyB64, publicKeyB64)], vault.rooms || [], vault.contacts || []];
	console.log('connectVaultLocalApp', resp);
	return resp;
};
</script>
