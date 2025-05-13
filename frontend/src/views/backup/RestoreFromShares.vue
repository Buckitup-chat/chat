<template>
	<div>
		<template v-if="!secretText">
			<div class="_divider mb-2">
				Provide shares
				<InfoTooltip class="align-self-center ms-2" :content="'To restore secret you must provide required number of shares backup was created with (Restore treshold)'" />
			</div>

			<div class="_input_block">
				<div class="mb-2" v-for="(share, idx) in shares">
					<div class="d-flex justify-content-between align-items-center">
						<div class="fw-bold mb-1">Share # {{ idx + 1 }}</div>
						<i class="_icon_times bg-dark _pointer" @click="shares.splice(idx, 1)" v-if="shares.length > 1"></i>
					</div>
					<textarea class="form-control" rows="3" placeholder="decrypted share from trusted partie" v-model="shares[idx]"></textarea>
				</div>
			</div>

			<div class="row justify-content-center gx-2 mt-3">
				<div class="col-lg-12 col-xl-10 mb-2">
					<button type="button" class="btn btn-dark w-100" @click="shares.push('')">Add share</button>
				</div>
				<div class="col-lg-12 col-xl-10 mb-2">
					<button type="button" class="btn btn-dark w-100" @click="recover()" :disabled="!shares.find((v) => v?.trim().length)">Restore</button>
				</div>
			</div>
		</template>

		<template v-if="secretText && !accountToRecover">
			<div class="_divider mb-2">Restored secret</div>

			<div class="_input_block text-break">
				{{ secretText }}
			</div>

			<div class="row justify-content-center gx-2 mt-2">
				<div class="col-lg-12 col-xl-10">
					<button type="button" class="btn btn-dark w-100" @click="copyToClipboard(secretText)">Copy</button>
				</div>
			</div>
		</template>

		<div class="row justify-content-center gx-2" v-if="accountToRecover">
			<div class="_divider mb-3">
				{{ isInVault ? 'Existing account' : 'Account found' }}
			</div>
			<div class="fs-4 mb-4 text-center">
				<span class="fw-bold">{{ accountToRecover.name ? accountToRecover.name : 'Unnamed' }}</span>
				<span class="text-secondary ms-2">[{{ accountToRecover.publicKey.slice(-5) }}]</span>
			</div>

			<div class="col-30 col-md-20">
				<button type="button" class="btn btn-dark btn-lg w-100" @click="addAccount()">
					{{ isInVault ? 'Overwrite account' : 'Restore account' }}
				</button>
			</div>
		</div>
	</div>
</template>

<style lang="scss" scoped>
//@import '@/scss/variables.scss';
</style>

<script setup>
import { ref, onMounted, watch, inject, computed } from 'vue';
import errorMessage from '@/utils/errorMessage';
import axios from 'axios';
import { decryptWithPrivateKey, cipher } from 'eth-crypto';
import copyToClipboard from '@/utils/copyToClipboard';

const shares = ref([]);
const $web3 = inject('$web3');
const $swal = inject('$swal');
const $user = inject('$user');
const $appstate = inject('$appstate');
const $encryptionManager = inject('$encryptionManager');
const $swalModal = inject('$swalModal');
const secretText = ref();
const accountToRecover = ref();
const offchainData = ref();

const emit = defineEmits(['restore', 'account']);

onMounted(async () => {
	$user.vaults = await $encryptionManager.getVaults();
	if ($appstate.value.shareToRestore) {
		shares.value.push($appstate.value.shareToRestore);
		$appstate.value.shareToRestore = null;
	} else {
		shares.value.push('');
	}
});

const isInVault = computed(() => {
	return $user.vaults.find((e) => e.publicKey === accountToRecover.value.publicKey);
});

const addAccount = async () => {
	try {
		const acc = await $user.generateAccount(accountToRecover.value.privateKey);

		const idx = $user.vaults.findIndex((a) => a.publicKey === acc.publicKey);
		if (idx > -1) {
			const confirmed = await $swalModal.value.open({
				id: 'confirm',
				title: 'Account restore',
				content: `
                    Account <strong>${accountToRecover.value.name}</strong> already present on this device.
                    <br> Are you sure you want to replace it with one from backup?
                    `,
			});
			if (!confirmed) return;
			if ($user.account) await $user.logout();
			await $encryptionManager.removeVault($user.vaults[idx].vaultId);
			$user.vaults = await $encryptionManager.getVaults();
		} else {
			if ($user.account) await $user.logout();
		}

		await $encryptionManager.createVault({
			keyOptions: {
				username: accountToRecover.value.name,
				displayName: accountToRecover.value.name,
			},
			address: acc.address,
			publicKey: acc.publicKey,
			avatar: accountToRecover.value.avatar,
			notes: accountToRecover.value.notes,
		});

		$user.account = acc;

		await $user.openStorage({
			accountInfo: {
				name: accountToRecover.value.name,
				notes: accountToRecover.value.notes,
				avatar: accountToRecover.value.avatar,
			},
		});

		if (offchainData.value) {
			try {
				const extra = (await axios.get(IPFS_URL + offchainData.value)).data;
				const decrypted = await decryptWithPrivateKey(accountToRecover.value.privateKey.slice(2), extra);
				const decoded = JSON.parse(decrypted);
				//if (decoded.contacts) await $user.initializeContacts(decoded.contacts);
			} catch (error) {
				console.error('initializeContacts', error);
			}
		}
	} catch (error) {
		console.error(error);
		$swal.fire({
			icon: 'error',
			title: 'Recover error',
			footer: errorMessage(error),
			timer: 30000,
		});
	}

	emit('account');
};

const recover = () => {
	try {
		secretText.value = $web3.bukitupClient.recoverSecret(shares.value.filter((v) => v?.trim().length));
		emit('restore', secretText.value);
		checkAccountRestore(secretText.value);
	} catch (error) {
		console.error(error);
		$swal.fire({
			icon: 'error',
			title: 'Recover error',
			footer: errorMessage(error),
			timer: 30000,
		});
	}
};

const checkAccountRestore = async (s) => {
	try {
		const decoded = JSON.parse(s);
		if (decoded.account && decoded.account.privateKey) {
			accountToRecover.value = decoded.account;
			offchainData.value = decoded.offchain;
		}
	} catch (error) {
		console.error(error);
	}
};
</script>
