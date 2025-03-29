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

		<template v-if="secretText && !account">
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

		<div class="row justify-content-center gx-2" v-if="account">
			<div class="_divider mb-3">
				{{ isInVault ? 'Existing account' : 'Account found' }}
			</div>
			<div class="fs-4 mb-4 text-center">
				<span class="fw-bold">{{ account.name ? account.name : 'Unnamed' }}</span>
				<span class="text-secondary ms-2">[{{ account.publicKey.slice(-5) }}]</span>
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
import { Wallet } from 'ethers';
import { decryptWithPrivateKey, cipher } from 'eth-crypto';
import copyToClipboard from '@/utils/copyToClipboard';

const shares = ref([]);
const $web3 = inject('$web3');
const $swal = inject('$swal');
const $user = inject('$user');
const $appstate = inject('$appstate');
const $encryptionManager = inject('$encryptionManager');

const secretText = ref();
const account = ref();

const emit = defineEmits(['restore', 'account']);

onMounted(async () => {
	if ($appstate.value.shareToRestore) {
		shares.value.push($appstate.value.shareToRestore);
		$appstate.value.shareToRestore = null;
	} else {
		shares.value.push('');
	}
});

const isInVault = computed(() => {
	return $user.vaults.find((e) => e.publicKey === account.value.publicKey);
});

const addAccount = async () => {
	if (isInVault.value) {
	}
	try {
		await $user.logout();
		await $encryptionManager.createVault({
			keyOptions: {
				username: account.value.name,
				displayName: account.value.name,
			},
			address: account.value.address,
			publicKey: account.value.publicKey,
			avatar: account.value.avatar,
			notes: account.value.notes,
		});
		console.log('create create');
		$user.account = await $user.generateAccount(account.value.privateKey);

		await $user.createSpace();
		await $user.openSpace({
			name: account.value.name,
			notes: account.value.notes,
			avatar: account.value.avatar,
		});

		if (account.value.offchain) {
			try {
				const extra = (await axios.get(IPFS_URL + account.value.offchain)).data;
				const d = await decryptWithPrivateKey(account.value.privateKey.slice(2), extra);

				const decExtra = JSON.parse(d);

				if (decExtra.contacts) {
					await $user.initializeContacts(decExtra.contacts);
				}
			} catch (error) {
				console.log('initializeContacts', error);
			}
		}
	} catch (error) {
		console.log(error);
		$swal.fire({
			icon: 'error',
			title: 'Recover error',
			footer: errorMessage(error),
			timer: 30000,
		});
	}

	emit('account', account.value);
};

const recover = () => {
	try {
		secretText.value = $web3.bukitupClient.recoverSecret(shares.value.filter((v) => v?.trim().length));
		emit('restore', secretText.value);
		checkAccountRestore(secretText.value);
	} catch (error) {
		console.log(error);
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
		const dec = JSON.parse(s);

		if (dec.account && dec.account.privateKey) {
			console.log(acc);
			account.value = acc;
		}
	} catch (error) {
		console.log(error);
	}

	secretText.value = s;
};
</script>
