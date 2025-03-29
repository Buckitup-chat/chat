<template>
	<div class="">
		<div class="d-flex align-items-center justify-content-between mb-2">
			<div class="">
				<Account_Item v-if="contact" :account="contact" />
			</div>

			<div class="d-flex align-items-center" v-if="item.backups.length > 1">
				<i class="_icon_shares_num bg-black me-2"></i>
				<span class="fw-bold ms-2">{{ item.backups.length }} </span>
			</div>
		</div>

		<div class="row fw-bold fs-6" v-if="$breakpoint.gt('lg')">
			<div class="col-6">Tag</div>
			<div class="col-6 text-center">Note</div>
			<div class="col-6 text-center">Delay</div>
			<div class="col-6 text-center">Status</div>
			<div class="col-6 text-end">Action</div>
		</div>

		<BackupShareItem :backup="backupItem" :share="backupItem.share" :idx="idx" v-for="(backupItem, idx) in item.backups" :key="backupItem.tag + backupItem.share.idx" />
	</div>
</template>

<script setup>
import BackupShareItem from './Backup_Share_Item.vue';
import Account_Item from '@/components/Account_Item.vue';
import { ref, onMounted, watch, inject, computed } from 'vue';

const $timestamp = inject('$timestamp');
const $user = inject('$user');
const $web3 = inject('$web3');
const $swal = inject('$swal');
const $route = inject('$route');
const $loader = inject('$loader');
const $breakpoint = inject('$breakpoint');

const { item } = defineProps({
	item: { type: Object, required: true },
});

onMounted(async () => {
	console.log(item);
});

const contact = computed(() => {
	try {
		return $user.contacts.find((c) => c.address.toLowerCase() === item.wallet.toLowerCase());
	} catch (error) {}
});
</script>
