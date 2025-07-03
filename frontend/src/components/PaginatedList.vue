<template>
	<div v-if="data">
		<div class="d-flex align-items-center justify-content-between mb-2" v-if="data.query">
			<div>
				<select class="form-select" v-model="data.query.sort" @change="setPage(1)" v-if="data.items.length">
					<option class="fw-bold" v-for="option in sortFilters" :value="option.value">
						{{ option.text }}
					</option>
				</select>

				<div class="small text-center opacity-50" v-if="!data.fetching && data.fetched && !data.items.length">
					<span v-if="noRecordsText">
						{{ noRecordsText }}
					</span>
					<trn k="publication_copies.no_records" v-else> No records </trn>
				</div>
			</div>

			<div class="d-flex">
				<a href="#" class="d-flex align-items-center small" @click.prevent="getList()">
					<span v-if="!data.fetching"><trn k="publication_copies.reload"> Reload </trn></span>
					<span v-if="data.fetching"><trn k="publication_copies.loading"> Loading... </trn></span>
				</a>
			</div>
		</div>

		<div class="small" v-if="data.fetched">
			<div class="" v-for="(item, $index) in data.items" :key="item.id">
				<slot name="item" :item="item" :index="$index" :lenght="data.items.lenght"></slot>
			</div>

			<slot name="footer"></slot>
		</div>

		<Paginate :page-count="parseInt(data.totalPages)" :click-handler="setPage" :force-page="parseInt(data.query.page)"> </Paginate>
	</div>
</template>

<style lang="scss" scoped></style>

<script setup>
import { ref, onMounted, inject } from 'vue';
import axios from 'axios';
import Paginate from './Paginate.vue';

const $web3 = inject('$web3');

const dataDefault = {
	query: { sort: 'desc', page: 1, limit: 10 },
	items: [],
	totalPages: 0,
	totalResults: 0,
	fetching: false,
	fetched: false,
};

const data = ref(JSON.parse(JSON.stringify(dataDefault)));
const { query, url } = defineProps({
	query: { type: Function, required: true },
	url: { type: Function, required: true },
	noRecordsText: { type: String },
});

onMounted(() => {
	data.value = JSON.parse(JSON.stringify(dataDefault));
	getList();
});

const sortFilters = [
	{ text: 'Recent', value: 'desc' },
	{ text: 'Oldest', value: 'asc' },
];

function setPage(page) {
	data.value.query.page = page;
	getList();
}

async function getList() {
	data.value.fetching = true;
	try {
		const res = (await axios.get(API_URL + url, { params: { ...data.value.query, ...query, chainId: $web3.mainChainId } })).data;
		data.value.items = res.results;
		data.value.totalPages = res.totalPages;
		data.value.totalResults = res.totalResults;
	} catch (error) {
		console.error(error);
	}
	data.value.fetched = true;
	data.value.fetching = false;
}

defineExpose({ getList });
</script>
