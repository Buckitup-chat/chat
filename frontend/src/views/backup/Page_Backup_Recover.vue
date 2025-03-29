<template>
	<div v-if="$user.account">
		<div class="mb-2 fw-bold">Insert a tag</div>

		<div class="row gx-2">
			<div class="col-md-4">
				<div class="form-floating mb-3">
					<input type="text" v-model="tag" class="form-control" placeholder="tag" />
					<label for="secretTag">Tag</label>
				</div>
			</div>
			<div class="col-md-4">
				<button class="btn btn-primary mb-2 me-2" @click="find()" :disabled="!tag">Check</button>
			</div>
		</div>

		<BackupItem :backup="backup" class="mb-2" ref="backupRef" v-if="backup" />
	</div>
</template>

<script setup>
import BackupItem from './Backup_Item.vue';

import { ref, onMounted, watch, inject, onUnmounted } from 'vue';
import { useRoute, useRouter } from 'vue-router';
import axios from 'axios';

const $user = inject('$user');
const $socket = inject('$socket');
const $swal = inject('$swal');
const $web3 = inject('$web3');
const $loader = inject('$loader');

const $route = useRoute();
const $router = useRouter();

const backupRef = ref();
const tag = ref();
const backup = ref();

watch(
	() => tag.value,
	() => {
		backup.value = null;
	},
);

watch(
	() => $user.account?.address,
	() => {
		backup.value = null;
	},
);

onMounted(() => {
	$socket.on('BACKUP_UPDATE', updateData);
	if ($route.query.t) {
		tag.value = $route.query.t;
		find();
	}
});

watch(
	() => $route.query?.t,
	() => {
		if ($route.query.t) {
			tag.value = $route.query.t;
			find();
		}
	},
);

onUnmounted(() => {
	$socket.off('BACKUP_UPDATE', updateData);
});

const updateData = async (tagUpdate) => {
	if (tag.value?.trim() === tagUpdate) {
		find();
	}
};

const find = async () => {
	$loader.show();
	try {
		backup.value = (await axios.get(API_URL + '/backup/get', { params: { tag: tag.value, chainId: $web3.mainChainId } })).data;
		if (backup.value?.tag && $route.query.t != backup.value.tag) {
			$router.replace({ query: { t: backup.value.tag } });
		}
	} catch (error) {
		console.log(error);
		$swal.fire({
			icon: 'error',
			title: 'Scan error',
			footer: error.toString(),
			timer: 30000,
		});
	}
	$loader.hide();
};
</script>
