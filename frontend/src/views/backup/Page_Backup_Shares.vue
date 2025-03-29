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
					<TopBarReuseTemplate v-if="$user.accountInfo.registeredMetaWallet && $breakpoint.gte('lg')" />
				</div>
			</div>
		</template>
		<template #headerbottom v-if="$user.accountInfo.registeredMetaWallet && $breakpoint.lt('lg')">
			<TopBarReuseTemplate class="mt-2 pe-3" />
		</template>

		<template #content>
			<div class="_full_width_block">
				<Account_Activate_Reminder />

				<template v-if="$user.accountInfo.registeredMetaWallet">
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
import { utils } from 'ethers';
import { createReusableTemplate } from '@vueuse/core';

const [TopBarTemplate, TopBarReuseTemplate] = createReusableTemplate();

const $user = inject('$user');
const $web3 = inject('$web3');
const $swal = inject('$swal');
const $socket = inject('$socket');
const $loader = inject('$loader');
const backups = ref([]);

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
	$socket.on('BACKUP_UPDATE', updateData);
	data.value = JSON.parse(JSON.stringify(dataDefault));
	//if ($user.accountInfo?.registeredMetaWallet) getList();
	getList();
});

onUnmounted(async () => {
	$socket.off('BACKUP_UPDATE', updateData);
});

watch(
	() => $user.accountInfo?.registeredMetaWallet,
	async (newVal) => {
		if (newVal) {
			//getList();
		}
	},
);

const updateData = async (tagUpdate) => {
	try {
		const idx = backups.value.findIndex((b) => b.tag === tagUpdate);
		if (idx > -1) {
			const bk = (await axios.get(API_URL + '/backup/get', { params: { tag: tagUpdate, chainId: $web3.mainChainId } })).data;
			backups.value[idx] = bk;
		}
	} catch (error) {
		console.log(error);
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
	//if (!data.value.query.s) return;
	getList();
};

function setPage(page) {
	//data.value.query.page = page;
	getList();
}

const getList = async () => {
	$loader.show();
	data.value.fetching = true;
	try {
		const backups = [];
		const groupedBackups = {};
		let s;
		if (data.value.query.s?.length) {
			try {
				s = utils.computeAddress(data.value.query.s.trim());
			} catch (error) {
				console.log(error);
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

		for (let index = 0; index < bk.length; index++) {
			const backup = bk[index];

			for (let i = 0; i < backup.shares.length; i++) {
				const share = backup.shares[i];
				const stealthAddr = $web3.bukitupClient.getStealthAddressFromEphemeral($user.account.metaPrivateKey, share.ephemeralPubKey);

				if (stealthAddr.toLowerCase() === share.stealthAddress.toLowerCase()) {
					backups.push(backup);
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
					}); // Grouping backups by owner

					break;
				}
			}
		}
		const groupedArray = Object.values(groupedBackups);

		data.value.items = groupedArray;
		console.log(groupedArray);
		data.value.totalPages = 1;
		data.value.totalResults = groupedArray.length;
	} catch (error) {
		console.log(error);
		$swal.fire({
			icon: 'error',
			title: 'Fetch error',
			footer: error.toString(),
			timer: 30000,
		});
	}
	$loader.hide();
	data.value.fetched = true;
	data.value.fetching = false;
	data.value.searched = true;
};
</script>
