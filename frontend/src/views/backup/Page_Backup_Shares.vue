<template>
	<TopBarTemplate>
		<div class="d-flex align-items-center justify-content-between">
			<div class="d-flex align-items-center w-100">
				<div class="_search flex-grow-1">
					<div class="_input_search ps-2">
						<input class="" type="text" v-model="data.query.s" autocomplete="off" placeholder="find by backup tag..." />

						<div class="_icon_times" v-if="data.query.s" @click="resetSearch()"></div>
					</div>
				</div>

				<div class="d-flex">
					<button class="btn btn-dark ms-1 rounded-pill d-flex align-items-center flex-fill py-2" @click="search()">
						<i class="_icon_search bg-white"></i>
						<span class="d-none d-sm-block ms-2">{{ data.query.s ? 'Search' : 'Scan' }}</span>
					</button>

					<button class="btn btn-dark ms-1 rounded-pill" @click="getList()">
						<i class="_icon_reload bg-white"></i>
					</button>
				</div>
			</div>
		</div>
	</TopBarTemplate>

	<FullContentBlock v-if="$user.account">
		<template #header>
			<div class="d-flex align-items-center justify-content-between w-100 pe-3">
				<div class="fw-bold fs-5 py-1">My shares</div>
				<div class="d-flex align-items-center">
					<TopBarReuseTemplate v-if="$user.registeredMetaWallet && $breakpoint.gte('lg')" />
				</div>
			</div>
		</template>
		<template #headerbottom v-if="$user.registeredMetaWallet && $breakpoint.lt('lg')">
			<TopBarReuseTemplate class="mt-2 pe-3" />
		</template>

		<template #content>
			<div class="_full_width_block">
				<Account_Activate_Reminder />
				<Offline_Reminder />
				<template v-if="$user.registeredMetaWallet">
					<div class="_divider" v-if="!data.searched">
						Find your shares
						<InfoTooltip class="align-self-center ms-2" :content="'Find your shares'" />
					</div>

					<div class="text-center fs-4 mb-3 text-secondary" v-if="!data.searched">
						Scan all to find all shares created for your stealth addresses. Or search by backup tag, creator public key or wallet address
					</div>

					<div v-if="data.fetched">
						<div v-if="!data.items.length">
							<div class="text-center fs-2 mb-1">No shares found</div>
						</div>
						<div class="_data_block mb-3" v-for="(item, $index) in data.items" :key="item.fetchTimestamp">
							<Backup_OwnerGroup_Item :item="item" />
						</div>
					</div>

					<Paginate :page-count="parseInt(data.totalPages)" :click-handler="setPage" :force-page="parseInt(1)"> </Paginate>
				</template>
			</div>
		</template>
	</FullContentBlock>
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
@import '@/scss/breakpoints.scss';
._full_width_block {
	//max-width: 40rem;
	width: 100%;
}
._search {
	height: 2.2rem;
	@include media-breakpoint-up(sm) {
		height: 2.5rem;
	}
}
</style>

<script setup>
import Backup_OwnerGroup_Item from './Backup_OwnerGroup_Item.vue';
import Paginate from '@/components/Paginate.vue';
import { ref, onMounted, watch, inject, onUnmounted } from 'vue';
import axios from 'axios';
import FullContentBlock from '@/components/FullContentBlock.vue';
import Account_Activate_Reminder from '@/components/Account_Activate_Reminder.vue';
import { computeAddress } from 'ethers';
import { createReusableTemplate } from '@vueuse/core';
import Offline_Reminder from '../../components/Offline_Reminder.vue';

const [TopBarTemplate, TopBarReuseTemplate] = createReusableTemplate();

const $user = inject('$user');
const $web3 = inject('$web3');
const $swal = inject('$swal');
const $socket = inject('$socket');
const $loader = inject('$loader');

let stealthAddresses = [];

const dataDefault = {
	query: { sort: 'desc', s: '' },
	items: [],
	totalPages: 0,
	totalResults: 0,
	fetching: false,
	fetched: false,
	searched: false,
};

const data = ref(JSON.parse(JSON.stringify(dataDefault)));

onMounted(async () => {
	if (!$socket.connected && $user.isOnline) $socket.connect();

	$socket.on('BACKUP_UPDATE', backupUpdateListener);
	$socket.on('DISPATCH', dispatchListener);

	data.value = JSON.parse(JSON.stringify(dataDefault));
	await $user.checkMetaWallet();
	getList();
});

onUnmounted(async () => {
	$socket.off('BACKUP_UPDATE', backupUpdateListener);
	$socket.off('DISPATCH', dispatchListener);

	if ($socket.connected) $socket.disconnect();
});

watch(
	() => $user.registeredMetaWallet,
	() => {
		getList();
	},
);

const dispatchListener = async (tx) => {
	if (tx.status === 'PROCESSING') {
		for (let i = 0; i < data.value.items.length; i++) {
			const group = data.value.items[i];
			for (let b = 0; b < group.backups.length; b++) {
				const backup = group.backups[b];
				if (backup.tag === tx.methodData.tag) {
					if (data.value.items[i].backups[b].share.idx === tx.methodData.idx) {
						data.value.items[i].backups[b].share.processingTx = tx;
						data.value.items[i].backups[b].share.fetchTimestamp++;
					}
				}
			}
		}
	}
};

const backupUpdateListener = async (backupUpdateData) => {
	try {
		if (!$user.account || !$user.account.metaPrivateKey) return;

		for (let i = 0; i < data.value.items.length; i++) {
			const group = data.value.items[i];
			for (let b = 0; b < group.backups.length; b++) {
				const backup = group.backups[b];
				if (backup.tag === backupUpdateData.backup.tag) {
					const share = backupUpdateData.backup.shares.find((s) => s.id === backup.share.id);
					if (share) {
						data.value.items[i].backups[b] = {
							wallet: backupUpdateData.backup.wallet,
							createdAt: backupUpdateData.backup.createdAt,
							disabled: backupUpdateData.backup.disabled,
							id: backupUpdateData.backup.id,
							fetchTimestamp: backupUpdateData.backup.fetchTimestamp,
							tag: backupUpdateData.backup.tag,
							treshold: backupUpdateData.backup.treshold,
							share,
						};
						const stAddr = stealthAddresses.find((s) => s.toLowerCase() === backupUpdateData.stealthAddress.toLowerCase());
						if (backupUpdateData.action === 'requestRecover' && stAddr) {
							$swal.fire({
								icon: 'success',
								title: 'Requested recovery',
								timer: 5000,
							});
						}
					}
				}
			}
		}
	} catch (error) {
		console.error('Page_Backup_Shares updateData', error);
	}
};

const resetSearch = async () => {
	data.value.query.s = null;
	data.value.fetched = false;
	data.value.items = [];
	data.value.totalPages = 0;
	data.value.totalResults = 0;
	getList();
};

const search = async () => {
	getList();
};

function setPage() {
	getList();
}

const getList = async () => {
	if (!$user.isOnline || !$user.account || !$user.account.metaPrivateKey) return;
	$loader.show();
	data.value.fetching = true;
	try {
		const groupedBackups = {};
		let s;
		if (data.value.query.s?.length) {
			try {
				s = computeAddress(data.value.query.s.trim());
			} catch (error) {
				console.error(error);
			}

			if (!s) {
				s = data.value.query.s;
			}
		}
		const bk = (
			await axios.get(API_URL + '/backup/getAll', {
				params: {
					s,
					chainId: $web3.mainChainId,
				},
			})
		).data;

		let stAddresses = [];
		// Grouping backups by owner
		for (let index = 0; index < bk.length; index++) {
			const backup = bk[index];

			for (let i = 0; i < backup.shares.length; i++) {
				const share = backup.shares[i];
				const stealthAddr = $web3.bukitupClient.getStealthAddressFromEphemeral($user.account.metaPrivateKey, share.ephemeralPubKey);

				if (stealthAddr.toLowerCase() === share.stealthAddress.toLowerCase()) {
					stAddresses.push(stealthAddr.toLowerCase());
					if (!groupedBackups[backup.wallet]) {
						groupedBackups[backup.wallet] = {
							wallet: backup.wallet,
							fetchTimestamp: backup.fetchTimestamp,
							backups: [],
						};
					}
					groupedBackups[backup.wallet].backups.push({
						wallet: backup.wallet,
						createdAt: backup.createdAt,
						disabled: backup.disabled,
						id: backup.id,
						fetchTimestamp: backup.fetchTimestamp,
						tag: backup.tag,
						treshold: backup.treshold,
						share,
					});
					break;
				}
			}
		}
		stealthAddresses = stAddresses;
		const groupedArray = Object.values(groupedBackups);
		data.value.items = groupedArray;
		data.value.totalPages = 1;
		data.value.totalResults = groupedArray.length;
	} catch (error) {
		console.error(error);
		//$swal.fire({
		//	icon: 'error',
		//	title: 'Fetch error',
		//	footer: error.toString(),
		//	timer: 30000,
		//});
	}
	$loader.hide();
	data.value.fetched = true;
	data.value.fetching = false;
	data.value.searched = true;
};
</script>
