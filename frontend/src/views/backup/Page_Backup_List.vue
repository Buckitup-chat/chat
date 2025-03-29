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
						<span class="d-none d-sm-block ms-2">Search</span>
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
				<div class="fw-bold fs-5 py-1">My backups</div>
				<div class="d-flex align-items-center">
					<TopBarReuseTemplate v-if="$user.accountInfo.registeredMetaWallet && $breakpoint.gte('lg')" />
					<button class="btn btn-dark rounded-pill ms-1 d-flex align-items-center justify-content-center py-2" @click="$router.push({ name: 'backup_create' })">
						<i class="_icon_plus bg-white"></i>
						<span class="ms-2" v-if="$breakpoint.gte('sm')">Create</span>
					</button>
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
					<div v-if="data.fetched">
						<div v-if="!data.items.length" class="mt-3">
							<div class="text-center fs-2 mb-3">No backups found</div>

							<div class="row justify-content-center gx-2 mb-2" v-if="!data.searched">
								<div class="col-lg-12 col-xl-10">
									<button type="button" class="btn btn-dark w-100" @click="$router.push({ name: 'backup_create' })" :disabled="false">Create backup</button>
								</div>
							</div>
						</div>
						<div class="_data_block mb-3" v-for="(backup, $index) in data.items" :key="backup.id">
							<BackupItem :backup="backup" />
						</div>
					</div>

					<Paginate :page-count="parseInt(data.totalPages)" :click-handler="setPage" :force-page="parseInt(data.query.page)"> </Paginate>
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
import FullContentBlock from '@/components/FullContentBlock.vue';
import Account_Activate_Reminder from '@/components/Account_Activate_Reminder.vue';
import { createReusableTemplate } from '@vueuse/core';

import BackupItem from './Backup_Item.vue';
import Paginate from '@/components/Paginate.vue';
import { ref, onMounted, inject, onUnmounted, watch } from 'vue';
import axios from 'axios';

const $router = inject('$router');
const $web3 = inject('$web3');
const $user = inject('$user');
const $socket = inject('$socket');
const $loader = inject('$loader');
const $swal = inject('$swal');

const [TopBarTemplate, TopBarReuseTemplate] = createReusableTemplate();

const dataDefault = {
	query: { sort: 'desc', page: 1, limit: 5, s: '' },
	items: [],
	totalPages: 0,
	totalResults: 0,
	fetching: false,
	fetched: false,
	searched: false,
};

const data = ref(JSON.parse(JSON.stringify(dataDefault)));

onMounted(() => {
	$socket.on('BACKUP_UPDATE', updateData);
	data.value = JSON.parse(JSON.stringify(dataDefault));
	getList();
});

onUnmounted(async () => {
	$socket.off('BACKUP_UPDATE', updateData);
});

watch(
	() => $user.accountInfo?.registeredMetaWallet,
	async (newVal) => {
		if (newVal) {
			getList();
		}
	},
);

const resetSearch = async () => {
	data.value.query.s = null;
	data.value.fetched = false;
	data.value.items = [];
	data.value.totalPages = 0;
	data.value.totalResults = 0;
	getList();
};

const search = async () => {
	if (!data.value.query.s) return;
	getList();
};

const updateData = async (tagUpdate) => {
	try {
		const idx = data.value.items.findIndex((b) => b.tag === tagUpdate);
		if (idx > -1) {
			const bk = (await axios.get(API_URL + '/backup/get', { params: { tag: tagUpdate, chainId: $web3.mainChainId } })).data;
			data.value.items[idx] = bk;
		}
	} catch (error) {
		console.log(error);
	}
};

function setPage(page) {
	data.value.query.page = page;
	getList();
}

async function getList() {
	$loader.show();
	data.value.fetching = true;
	try {
		const res = (
			await axios.get(API_URL + '/backup/getList', {
				params: {
					...data.value.query,
					wallet: $user.account?.address,
					chainId: $web3.mainChainId,
				},
			})
		).data;
		data.value.items = res.results;
		data.value.totalPages = res.totalPages;
		data.value.totalResults = res.totalResults;
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
	if (data.value.query.s) data.value.searched = true;
}
</script>
