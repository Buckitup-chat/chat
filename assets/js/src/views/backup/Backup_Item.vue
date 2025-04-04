<template>
	<div class="">
		<div class="row">
			<div class="col-30 col-xl-20 d-flex justify-content-start align-items-center mb-2">
				<div class="text-wrap text-break fw-bold fs-5" style="white-space: pre" v-if="comment && isOwner">
					{{ comment.trim() }}
				</div>
			</div>

			<div class="col-30 col-xl-10 d-flex justify-content-between justify-content-xl-end align-items-center text-center mb-2">
				<div v-tooltip="`Created ${$date(backup.createdAt).format('DD-MM-YY HH:mm')}`">
					{{ $date(backup.createdAt).fromNow() }}
				</div>

				<div class="rounded-pill bg-success text-white d-flex align-items-center px-3 py-1 ms-2">
					<div class="_icon_gnossis_chain bg-white me-2"></div>
					Gnosis
				</div>
			</div>
		</div>

		<div class="d-flex align-items-center justify-content-between mb-2">
			<div class="d-flex align-items-center">
				<i class="_icon_tag bg-black me-2"></i>
				<div class="fw-bold text-primary _pointer" v-tooltip="`Unique tag. Click to select`">
					{{ backup.tag }}
				</div>

				<i class="_icon_copy bg-black ms-3 _pointer" @click="copyToClipboard(backup.tag)" v-tooltip="`Copy tag`"></i>
			</div>

			<div class="d-flex align-items-center" v-if="backup.shares.length > 1">
				<i class="_icon_shares_num bg-black me-2"></i>
				<div>Treshold</div>
				<span class="fw-bold ms-2"
					>{{ backup.treshold }} <span v-if="!isOwner">of {{ backup.shares.length }} parties</span></span
				>
				<InfoTooltip class="align-self-center ms-2" :content="'Required number of shares to recover secret'" />
			</div>
		</div>

		<div class="row fw-bold fs-6" v-if="$breakpoint.gt('lg')">
			<div class="col-12 d-flex justify-content-start align-items-center text-center">User</div>
			<div class="col-6 d-flex justify-content-center align-items-center text-center">
				Delay
				<InfoTooltip class="align-self-center ms-2" :content="'During this time owner can decline reading by trusted user. After time past secret is revealed'" />
			</div>
			<div class="col-6 d-flex justify-content-center align-items-center text-center">Status</div>
			<div class="col-6 d-flex justify-content-end align-items-center text-center">Action</div>
		</div>

		<BackupShareItem :backup="backup" :share="share" :idx="idx" v-for="(share, idx) in backup.shares" :key="backup.id + share.idx" />

		<div class="d-flex align-items-center justify-content-between mb-2" v-if="false && isOwner && !isUnlocked">
			<div class="d-flex align-items-center">
				<span class="fw-bold text-danger" v-if="backup.disabled">Disabled</span>
				<span class="fw-bold" v-else>Active</span>
				<InfoTooltip class="align-self-center ms-2" :content="'Active/Disabled'" />
			</div>

			<div>
				<button type="button" class="btn btn-dark btn-sm" @click="updateBackupDisabled()" v-if="isOwner && !isUnlocked">{{ backup.disabled ? 'Enable' : 'Disable' }}</button>
			</div>
		</div>

		<div :class="[backup.processingTx && isOwner ? '_input_block mt-2' : 'd-none']">
			<div class="small mb-2">Latest transaction</div>
			<Transactions :list="backup.processingTx ? [backup.processingTx] : null" only-last="true" />
		</div>
	</div>
</template>

<script setup>
import BackupShareItem from './Backup_Share_Item.vue';
import { ref, onMounted, watch, inject, computed } from 'vue';
import { decryptWithPrivateKey, cipher } from 'eth-crypto';
import copyToClipboard from '@/libs/copyToClipboard';
import axios from 'axios';
import Transactions from '@/views/account/Transactions.vue';

const $timestamp = inject('$timestamp');
const $user = inject('$user');
const $web3 = inject('$web3');
const $swal = inject('$swal');
const $loader = inject('$loader');
const $swalModal = inject('$swalModal');

const { backup } = defineProps({
	backup: { type: Object, required: true },
});

onMounted(async () => {
	init();
});

watch(
	() => backup,
	() => {
		init();
	},
	{ deep: true },
);

const comment = ref();

const isOwner = computed(() => {
	return backup.wallet.toLowerCase() == $user.account?.address?.toLowerCase();
});

const isUnlocked = computed(() => {
	return !backup.shares.find((s) => !s.unlocked);
});

const init = async () => {
	if (isOwner.value) {
		try {
			comment.value = await decryptWithPrivateKey($user.account.metaPrivateKey.slice(2), cipher.parse(backup.commentEncrypted.slice(2)));
		} catch (error) {
			console.error('comment', error);
		}
	}
};

const updateBackupDisabled = async () => {
	if (!$user.checkOnline()) return;
	if (
		!(await $swalModal.value.open({
			id: 'confirm',
			title: backup.disabled ? 'Enabling backup' : 'Disabling backup',
			content: 'Confirm transaction',
		}))
	)
		return;

	try {
		$loader.show();

		const expire = $timestamp.value + 300;
		const domain = {
			name: 'BuckitUpVault',
			version: '1',
			chainId: $web3.mainChainId,
			verifyingContract: $web3.bc.vault.address,
		};
		const types = {
			UpdateBackupDisabled: [
				{ name: 'tag', type: 'string' },
				{ name: 'disabled', type: 'uint8' },
				{ name: 'expire', type: 'uint40' },
			],
		};
		const message = {
			tag: backup.tag,
			disabled: backup.disabled ? 0 : 1,
			expire,
		};
		const signature = await $web3.signTypedData($user.account.privateKey, domain, types, message);

		await axios.post(API_URL + '/dispatch/updateBackupDisabled', {
			wallet: $user.account?.address,
			chainId: $web3.mainChainId,
			tag: backup.tag,
			disabled: backup.disabled ? 0 : 1,
			expire,
			signature,
		});

		$swal.fire({
			icon: 'success',
			title: 'Update backup',
			footer: 'Please wait for transaction confirmation',
			timer: 5000,
		});
	} catch (error) {
		console.error(error);
		$swal.fire({
			icon: 'error',
			title: 'Update backup error',
			footer: error.toString(),
			timer: 30000,
		});
	}
	$loader.hide();
};
</script>
