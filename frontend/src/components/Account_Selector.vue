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
import { computed, inject, ref, onMounted, watch, nextTick } from 'vue';
import Account_Item from '@/components/Account_Item.vue';

const $mitt = inject('$mitt');
const $loader = inject('$loader');
const $web3 = inject('$web3');
const $user = inject('$user');
const $swal = inject('$swal');
const $router = inject('$router');
const $route = inject('$route');
const $swalModal = inject('$swalModal');
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

		swalInstance = $swal.fire({
			icon: 'info',
			title: 'Authenticate with PassKey',
			footer: 'Please confirn PassKey on your device when it prompts',
		});

		await $encryptionManager.connectToVault(nextUser.vaultId);
		swalInstance.close();
		if (!$encryptionManager.isAuth) {
			$loader.hide();
			return;
		}
		$user.account = await $user.fromVaultFormat(await $encryptionManager.getData());

		if ($user.account.spaceId) {
			const spaces = $user.dxClient.spaces.get();
			const space = spaces.find((s) => s.id === $user.account.spaceId);
			//console.log('Space of user', $user.account.spaceId);
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

		try {
			if (!$user.accountInfo.registeredMetaWallet) {
				const metaPublicKey = await $web3.registryContract.metaPublicKeys($user.account.address);
				if (metaPublicKey && metaPublicKey.length > 2) {
					$user.accountInfo.registeredMetaWallet = true;
				}
			}
		} catch (error) {
			console.log('metaPublicKey', error);
		}

		nextTick(() => {
			try {
				$router.push({ name: 'account_info' });
			} catch (error) {
				console.log('signin', error);
			}
		});

		$mitt.emit('modal::close');
	} catch (error) {
		console.log('signin', error);
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
	await $user.updateVault();
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

const testContacts = {
	'0xd292bd04cecd27f8ff12dad85b71b1d62a6da29863a94341ac618a5049494f9f': [
		{
			publicKey: '0x02bf7a036d76c748bcd23619d0961eff9f813715e3df83562c90d48c100ef2b7cc',
			address: '0xAc3e4a2D4609309A837DF653Cbd71b1589bb2E65',
			name: 'Arkadiy',
			notes: 'BuckitUp boss',
		},
		{
			publicKey: '0x02ee7928ca1750ce9fc0e870a780087f2bd5b5fed29d6a3b9cfd82004bb755f4b1',
			address: '0xAC31746448cdcC7e72915F68185372FF63a10279',
			name: 'Sergey',
			notes: 'BuckitUp lead dev',
		},
		{
			address: '0x7257253d64871377f3563cB533aF715927CE5Ea9',
			publicKey: '0x02e066aae9b2f0efe43b0f604b1398ce38914e77cb61c645bb5bdde61a07523ee8',
			name: 'Alice Johnson',
			notes: 'A long-time friend and crypto enthusiast.',
			avatar: 'bafybeicmqczqlcfstoc242b4rfgdcsiyr7znqczisqfjxmrgoh5w4w7owi',
		},
		{
			address: '0x96103B125c6FD386B1901138d1Ebfcad18A70d29',
			publicKey: '0x02883c1f0e26d20fbf7944fbf0662e2e21e6c8416b11b7778671a8555a38f9a847',
			name: 'Bob Smith',
			notes: 'Met at a blockchain conference last year.',
			avatar: 'bafybeiey4mhhezratch34l2py5jycdnk2l4bvp2oe26pr3pwmfd2jdjkxa',
		},
		{
			address: '0x4cb87d2842691b21529082189839Dd6F9f82a7Fd',
			publicKey: '0x03cb59130c8daef1ad3a9c59509bdf7a6ee20c112020317acdc5edaf2f4b3cc8a4',
			name: 'Charlie Brown',
			notes: 'Trusted trader and NFT collector.',
			avatar: 'bafybeic7vhotto7c4kqgzmlechjjgbsrhyigzznl3e5wriuhpa527hqk64',
		},
		{
			address: '0x699756A0c4663C04a87E1bF8b85ff165BADEd0dE',
			publicKey: '0x0245934e1ace7a0cedb723f15893b3985179061f62e98e6cbbe1c9698fce09f977',
			name: 'David Taylor',
			notes: 'Specializes in decentralized finance (DeFi).',
		},
		{
			address: '0x46d66a7EE137bD896E63f62658028Bb7DeAe9504',
			publicKey: '0x02581d24eca4173aa9e06a85cd8e0548adf3605da210eb5a3eb2a22ac38b930cb5',
			name: 'Eve Anderson',
			notes: 'Always up to date with the latest crypto trends.',
		},
		{
			address: '0xaA5AD169584DE3a4081d7eEaDeB88B48F3Fc99A3',
			publicKey: '0x02db0d7100bf402b89069d11fc6701bdca52e0876a38a7d09c8808782e3c31d89f',
			name: 'Frank Thomas',
			notes: 'We collaborated on a smart contract project.',
		},
		{
			address: '0x84B225D89C5D98882C3fBB054e45403C2943C483',
			publicKey: '0x029ab62a5d196300dbe031050a8b91581982ea25e25cfe2f22ae4c853e10d8cc34',
			name: 'Grace White',
			notes: 'Knows a lot about Ethereum staking strategies.',
		},
		{
			address: '0x1904937662053BD2c55E12F5782c9D82A7A76E82',
			publicKey: '0x02e8582fabb113ed79864ede4eb100bb21cd3afde042e28deee0db3fbee1b074fc',
			name: 'Hannah Harris',
			notes: 'Runs a YouTube channel about crypto investing.',
		},
		{
			address: '0x82B97cC2003832594EE8f70eFC21dDa5A2FF2eC1',
			publicKey: '0x0306e297502b67f2746eb0112f0a26a8189b56a24f2b2759848eb362b1af70cdcb',
			name: 'Ivan Martin',
			notes: 'A passionate advocate for Web3 and privacy.',
		},
		{
			address: '0xB096bF7842401EFB33A1950a022C11061Ea23298',
			publicKey: '0x0244cdc749381572f5b501b89efbc4ba398d594323a1b83be8e209684a5f95db7f',
			name: 'Julia Thompson',
			notes: 'Highly skilled in Solidity and dApp development.',
		},
	],
	'0xd20ac7cb8e3a8c9e655fa729f4e6d836717233874a8722bf92097b102576c4e2': [
		{
			publicKey: '0x028b1cc67b1524038c8445e0ab4a383d0bb02f4e75b8f7eee6bae33eff14781e7a',
			address: '0x748d9c35b6bFD0AD3E05d891Ad97855c314C49ED',
			name: 'Roman Chvankov',
			notes: 'Blockchain dev',
		},
		//{
		//  publicKey:
		//    "0x02ee7928ca1750ce9fc0e870a780087f2bd5b5fed29d6a3b9cfd82004bb755f4b1",
		//  address: "0xAC31746448cdcC7e72915F68185372FF63a10279",
		//  name: "Sergey",
		//  notes: "BuckitUp lead dev",
		//},
		{
			address: '0x7257253d64871377f3563cB533aF715927CE5Ea9',
			publicKey: '0x02e066aae9b2f0efe43b0f604b1398ce38914e77cb61c645bb5bdde61a07523ee8',
			name: 'Alice Johnson',
			notes: 'A long-time friend and crypto enthusiast.',
			avatar: 'bafybeicmqczqlcfstoc242b4rfgdcsiyr7znqczisqfjxmrgoh5w4w7owi',
		},
		{
			address: '0x96103B125c6FD386B1901138d1Ebfcad18A70d29',
			publicKey: '0x02883c1f0e26d20fbf7944fbf0662e2e21e6c8416b11b7778671a8555a38f9a847',
			name: 'Bob Smith',
			notes: 'Met at a blockchain conference last year.',
			avatar: 'bafybeiey4mhhezratch34l2py5jycdnk2l4bvp2oe26pr3pwmfd2jdjkxa',
		},
		{
			address: '0x4cb87d2842691b21529082189839Dd6F9f82a7Fd',
			publicKey: '0x03cb59130c8daef1ad3a9c59509bdf7a6ee20c112020317acdc5edaf2f4b3cc8a4',
			name: 'Charlie Brown',
			notes: 'Trusted trader and NFT collector.',
			avatar: 'bafybeic7vhotto7c4kqgzmlechjjgbsrhyigzznl3e5wriuhpa527hqk64',
		},
		{
			address: '0x699756A0c4663C04a87E1bF8b85ff165BADEd0dE',
			publicKey: '0x0245934e1ace7a0cedb723f15893b3985179061f62e98e6cbbe1c9698fce09f977',
			name: 'David Taylor',
			notes: 'Specializes in decentralized finance (DeFi).',
		},
	],
	'0x4a06275ea3f9d5bb57b72b2c6d59fdbc12dbf00fd1d1ef6e2df7040b705333c5': [
		//{
		//  publicKey:
		//    "0x02bf7a036d76c748bcd23619d0961eff9f813715e3df83562c90d48c100ef2b7cc",
		//  address: "0xAc3e4a2D4609309A837DF653Cbd71b1589bb2E65",
		//  name: "Arkadiy",
		//  notes: "BuckitUp boss",
		//},
		//{
		//  publicKey:
		//    "0x028b1cc67b1524038c8445e0ab4a383d0bb02f4e75b8f7eee6bae33eff14781e7a",
		//  address: "0x748d9c35b6bFD0AD3E05d891Ad97855c314C49ED",
		//  name: "Roman Chvankov",
		//  notes: "Blockchain dev",
		//}
	],
	'0xed0c62a9c2d2f8968ad14fb00a486653bae207cba2109720288912f065cc1e91': [],
};
</script>
