<template>
	<div class="border-top mt-2 pt-2" v-if="isOwner || isTrusted">
		<div class="row">
			<div class="col-30 col-xl-12 d-flex justify-content-start align-items-center">
				<div v-if="isOwner" class="mb-2 mb-xl-0">
					<!--a :href="$web3.blockExplorer + '/address/' + backup.wallet" target="_blank" rel="noopener noreferrer">
						{{ $filters.addressShort(backup.wallet) }}
					</a-->

					<div class="" v-if="contact" :class="{ _disabled: share.disabled }">
						<Account_Item :account="contact" />
					</div>
				</div>

				<div class="w-100 p-0" v-if="isTrusted">
					<div class="row">
						<div class="col-30 col-xl-12 d-flex justify-content-between align-items-center mb-2 mb-xl-0">
							<div class="fw-bold text-primary me-3" v-tooltip="`Created ${$date(backup.createdAt).format('DD-MM-YY HH:mm')}`">
								{{ backup.tag }}
							</div>
							<div v-tooltip="`Created ${$date(backup.createdAt).format('DD-MM-YY HH:mm')}`" v-if="$breakpoint.lte('lg')">
								{{ $date(backup.createdAt).fromNow() }}
							</div>
						</div>
						<div class="col-30 col-xl-18">
							<div class="mb-2 mb-xl-0 _pointer" :class="{ _truncate: truncated }" @click="truncated = !truncated">
								{{ message }}
							</div>
						</div>
					</div>
				</div>
			</div>
			<div class="col-30 col-xl-6 d-flex flex-column flex-xl-row justify-content-start justify-content-xl-center align-items-start align-items-xl-center">
				<div class="mb-1 d-block d-xl-none fw-bold">Recovery delay</div>

				<div class="_btn_block _blue" v-if="share.delay" @click="updateShareDelay()" :disabled="tx" :class="{ _disabled: share.disabled }">
					<i class="_icon_timer me-2"></i>
					<span class="fw-bold ms-1">{{ $filters.secondsToHMS(share.delay) }}</span>

					<div class="_badge _pointer" v-if="isOwner">
						<i class="_icon_edit_pen"></i>
					</div>
				</div>

				<div class="_btn_block _blue opacity-50" v-if="!share.delay">Not set</div>
			</div>
			<div class="col-30 col-xl-6 d-flex flex-column flex-xl-row justify-content-start justify-content-xl-center align-items-start align-items-xl-center mb-2 mb-xl-0">
				<div class="mb-1 d-block d-xl-none fw-bold">Status</div>
				<div class="_btn_block _grey" v-if="!share.unlocked && share.disabled">Disabled</div>
				<div class="_btn_block _red" v-if="share.unlocked">Unlocked</div>
				<div class="_btn_block _green" v-if="!share.unlocked && !share.disabled && !share.request">Secured</div>

				<div
					class="_btn_block _orange"
					v-if="share.request && !share.unlocked && timeLeft && !share.disabled"
					v-tooltip="`Requested ${$date.unix(share.request).format('DD-MM-YY HH:mm')}, Unlocks ${$date.unix(share.request + share.delay).format('DD-MM-YY HH:mm')}`"
				>
					<i class="_icon_unlock me-2"></i>
					{{ $date.unix(share.request + share.delay).fromNow() }}
				</div>
			</div>

			<div class="col-30 col-xl-6 d-flex justify-content-end align-items-center text-center">
				<div class="btn-group w-100" role="group" aria-label="Basic mixed styles example" v-if="isOwner">
					<button
						type="button"
						class="btn btn-outline-dark btn-sm w-100"
						@click="updateShareDisabled()"
						v-if="isOwner && !share.unlocked"
						:disabled="share.processingTx || backup.processingTx"
					>
						{{ share.disabled ? 'Enable' : 'Disable' }}
					</button>

					<button type="button" class="btn btn-outline-dark btn-sm w-100" @click="deleteBackup()" v-if="share.unlocked" :disabled="share.processingTx || backup.processingTx">Delete</button>

					<div class="btn-group" role="group" v-if="!share.unlocked">
						<button
							type="button"
							class="btn btn-outline-dark btn-sm dropdown-toggle px-3"
							data-bs-toggle="dropdown"
							aria-expanded="false"
							:disabled="share.processingTx || backup.processingTx"
						></button>
						<ul class="dropdown-menu">
							<li>
								<a class="dropdown-item d-flex align-items-center" href="#" v-if="isOwner" @click="updateShareDelay()">
									<i class="_icon_timer me-2"></i>
									Set recovery delay
								</a>
							</li>
							<li>
								<a class="dropdown-item d-flex align-items-center" href="#" @click.prevent="deleteBackup()" v-if="!share.unlocked && share.disabled">
									<i class="_icon_delete me-2"></i>
									Delete (hide from list)
								</a>
							</li>
						</ul>
					</div>
				</div>

				<div class="btn-group w-100" role="group" aria-label="Basic mixed styles example" v-if="share.stealthAddress?.toLowerCase() === stealthAddr?.toLowerCase()">
					<button type="button" class="btn btn-outline-dark btn-sm w-100" @click="requestRecover()" v-if="isRequestRequired" :disabled="share.processingTx">Request</button>

					<button type="button" class="btn btn-outline-danger btn-sm w-100" @click="requestRecover()" v-if="share.request && !share.unlocked" disabled>Requested</button>

					<button type="button" class="btn btn-outline-dark btn-sm" @click="recover('down')" v-if="!isRequestRequired && isRocoverable">Download</button>

					<div class="btn-group" role="group" v-if="share.unlocked">
						<button type="button" class="btn btn-outline-dark btn-sm dropdown-toggle px-3" data-bs-toggle="dropdown" aria-expanded="false"></button>
						<ul class="dropdown-menu">
							<li>
								<a class="dropdown-item d-flex align-items-center" href="#" @click.prevent="recover('restore')" v-if="!isRequestRequired && isRocoverable"> Restore </a>
							</li>
							<li>
								<a class="dropdown-item d-flex align-items-center" href="#" @click.prevent="recover('copy')" v-if="!isRequestRequired && isRocoverable"> Copy </a>
							</li>
							<li>
								<a class="dropdown-item d-flex align-items-center" href="#" @click.prevent="deleteBackup()" v-if="share.unlocked"> Delete (hide from list) </a>
							</li>
						</ul>
					</div>
				</div>
			</div>
		</div>

		<div :class="[share.processingTx && !isOwner ? '_input_block mt-2' : 'd-none']">
			<div class="small mb-2">Latest transaction</div>
			<Transactions :list="share.processingTx ? [share.processingTx] : null" only-last="true" />
		</div>
	</div>
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
@import '@/scss/breakpoints.scss';
._select_icon {
	height: 3rem;
	min-width: 3rem;
	width: 3rem;
	margin-right: 1rem;
	margin-top: 1rem;
}
._export_locally {
	margin-left: 4rem;
	width: 100%;
}
._btn_block {
	border: 1px solid #000000;
	background-color: #0000001e;
	display: flex;
	align-items: center;
	justify-content: center;
	padding: 0.18rem 0.2rem;
	width: 100%;
	border-radius: 0.25rem;
	position: relative;
	._badge {
		position: absolute;
		right: -5px;
		top: -5px;
		border-radius: 0.25rem;
		padding: 0.2rem;
		i {
			background-color: $white !important;
			height: 0.9rem;
			min-width: 0.9rem;
		}
	}
	&._grey {
		border-color: $grey_dark;
		background-color: rgba($grey_dark, 0.3);
		color: $grey_dark;
		i,
		._badge {
			background-color: $grey_dark;
		}
	}
	&._green {
		border-color: $green;
		background-color: rgba($green, 0.3);
		color: $green;
		i {
			background-color: $green;
		}
	}
	&._blue {
		border-color: $blue;
		background-color: rgba($blue, 0.3);
		color: $blue;
		i,
		._badge {
			background-color: $blue;
		}
	}
	&._orange {
		border-color: $orange;
		background-color: rgba($orange, 0.3);
		color: $orange;
		i,
		._badge {
			background-color: $orange;
		}
	}
	&._red {
		border-color: $red;
		background-color: rgba($red, 0.3);
		color: $red;
		i,
		._badge {
			background-color: $red;
		}
	}
}
._disabled {
	filter: grayscale(1) opacity(0.6) !important;
}
</style>

<script setup>
import { ref, onMounted, watch, inject, computed } from 'vue';
import { decryptToString } from '@lit-protocol/encryption';
import { cipher, decryptWithPrivateKey } from 'eth-crypto';
import copyToClipboard from '@/utils/copyToClipboard';
import { Wallet } from 'ethers';
import axios from 'axios';
import Account_Item from '@/components/Account_Item.vue';
import errorMessage from '@/utils/errorMessage';
import Transactions from '@/views/account/Transactions.vue';

const $timestamp = inject('$timestamp');
const $user = inject('$user');
const $web3 = inject('$web3');
const $swal = inject('$swal');
const $loader = inject('$loader');
const $swalModal = inject('$swalModal');
const $router = inject('$router');
const $appstate = inject('$appstate');
const shareDelay = ref();
const truncated = ref(true);

const { backup, share, idx } = defineProps({
	backup: { type: Object, required: true },
	share: { type: Object, required: true },
	idx: { type: Number, required: true },
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

const message = ref();
const privateKey = ref();
const stealthAddr = ref();
const address = ref();

const contact = computed(() => {
	let contact;
	try {
		contact = $user.contacts.find((c) => c.address.toLowerCase() === address.value.toLowerCase());
	} catch (error) {}

	try {
		if (!contact && stealthAddr.value) {
			contact = {
				address: stealthAddr.value,
			};
		}
	} catch (error) {}
	return contact;
});

const init = async () => {
	privateKey.value = null;
	shareDelay.value = share.delay;
	message.value = null;
	stealthAddr.value = $web3.bukitupClient.getStealthAddressFromEphemeral($user.account.metaPrivateKey, share.ephemeralPubKey);
	if (stealthAddr.value.toLowerCase() === share.stealthAddress.toLowerCase()) {
		privateKey.value = $web3.bukitupClient.generateStealthPrivateKey($user.account.metaPrivateKey, share.ephemeralPubKey);
		try {
			message.value = await decryptWithPrivateKey(privateKey.value.slice(2), cipher.parse(share.messageEncrypted.slice(2)));
		} catch (error) {
			console.error('message', error);
		}
	}
	if (isOwner.value && share.addressEncrypted) {
		address.value = await decryptWithPrivateKey($user.account.metaPrivateKey.slice(2), cipher.parse(share.addressEncrypted.slice(2)));
	}
};

const isRequestRequired = computed(() => {
	if (!privateKey.value) return false;
	if (share.request) return false;
	if (backup.disabled) return true;
	if (share.disabled) return true;
	if (share.delay) return true;
});

const isRocoverable = computed(() => {
	if (!privateKey.value) return false;
	if (backup.disabled) return false;
	if (share.disabled) return false;
	if (share.unlocked) return true;
});

const isOwner = computed(() => {
	return backup.wallet.toLowerCase() == $user.account?.address?.toLowerCase();
});

const isTrusted = computed(() => {
	return share.stealthAddress?.toLowerCase() === stealthAddr.value;
});

const timeLeft = computed(() => {
	if (share.request == 0) return 0;
	return Math.max(0, share.request + share.delay - $timestamp.value);
});

const updateShareDisabled = async () => {
	if (!$user.checkOnline()) return;

	if (!isOwner.value) return;
	if (
		!(await $swalModal.value.open({
			id: 'confirm',
			title: share.disabled ? 'Enabling share' : 'Disabling share',
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
			UpdateShareDisabled: [
				{ name: 'tag', type: 'string' },
				{ name: 'idx', type: 'uint8' },
				{ name: 'disabled', type: 'uint8' },
				{ name: 'expire', type: 'uint40' },
			],
		};
		const message = {
			tag: backup.tag,
			idx: share.idx,
			disabled: share.disabled ? 0 : 1,
			expire,
		};
		const signature = await $web3.signTypedData($user.account.privateKey, domain, types, message);

		await axios.post(API_URL + '/dispatch/updateShareDisabled', {
			wallet: $user.account.address,
			chainId: $web3.mainChainId,
			tag: backup.tag,
			idx: share.idx,
			disabled: share.disabled ? 0 : 1,
			expire,
			signature,
		});

		$swal.fire({
			icon: 'success',
			title: 'Update backup share',
			footer: 'Please wait for transaction confirmation',
			timer: 5000,
		});
	} catch (error) {
		console.error(error);
		$swal.fire({
			icon: 'error',
			title: 'Update backup share error',
			footer: errorMessage(error),
			timer: 30000,
		});
	}
	$loader.hide();
};

const updateShareDelay = async () => {
	if (!$user.checkOnline()) return;

	if (!isOwner.value) return;
	const newDelay = await $swalModal.value.open({
		id: 'update_backup_share_delay',
		currentDelay: share.delay,
	});

	if (newDelay === undefined || newDelay === false || newDelay == share.delay) return;

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
			UpdateShareDelay: [
				{ name: 'tag', type: 'string' },
				{ name: 'idx', type: 'uint8' },
				{ name: 'delay', type: 'uint40' },
				{ name: 'expire', type: 'uint40' },
			],
		};
		const message = {
			tag: backup.tag,
			idx: share.idx,
			delay: newDelay,
			expire,
		};
		const signature = await $web3.signTypedData($user.account.privateKey, domain, types, message);

		await axios.post(API_URL + '/dispatch/updateShareDelay', {
			wallet: $user.account.address,
			chainId: $web3.mainChainId,
			tag: backup.tag,
			idx: share.idx,
			delay: newDelay,
			expire,
			signature,
		});

		$swal.fire({
			icon: 'success',
			title: 'Update recovery delay',
			footer: 'Please wait for transaction confirmation',
			timer: 5000,
		});
	} catch (error) {
		console.error(error);
		$swal.fire({
			icon: 'error',
			title: 'Update recovery delay',
			footer: errorMessage(error),
			timer: 30000,
		});
	}
	$loader.hide();
};

const requestRecover = async () => {
	if (!$user.checkOnline()) return;

	if (
		!(await $swalModal.value.open({
			id: 'confirm',
			title: 'Recover request',
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
			RequestRecover: [
				{ name: 'tag', type: 'string' },
				{ name: 'idx', type: 'uint8' },
				{ name: 'expire', type: 'uint40' },
			],
		};
		const message = {
			tag: backup.tag,
			idx: share.idx,
			expire,
		};
		const wallet = new Wallet(privateKey.value);

		const signature = await $web3.signTypedData(privateKey.value, domain, types, message);

		await axios.post(API_URL + '/dispatch/requestRecover', {
			wallet: stealthAddr.value,
			chainId: $web3.mainChainId,
			tag: backup.tag,
			idx: share.idx,
			expire: expire,
			signature: signature,
		});

		$swal.fire({
			icon: 'success',
			title: 'Recover request',
			footer: 'Please wait for transaction confirmation',
			timer: 5000,
		});
	} catch (error) {
		console.error(error);
		$swal.fire({
			icon: 'error',
			title: 'Recover request',
			footer: errorMessage(error),
			timer: 30000,
		});
	}
	$loader.hide();
};

const recover = async (saveType) => {
	try {
		$loader.show();

		const signer = new Wallet(privateKey.value);

		console.log($web3.vaultContract);

		const checkAccess = await $web3.vaultContract.granted(backup.tag, share.idx, signer.address);
		if (!checkAccess) {
			$loader.hide();
			throw new Error('Not granted');
		}

		const capacityDelegationAuthSig = (
			await axios.post(API_URL + '/lit/getCreditsSign', {
				address: signer.address,
			})
		).data;

		const sessionSigs = await $web3.getSessionSigs(signer, capacityDelegationAuthSig);
		const unifiedAccessControlConditions = $web3.getAccessControlConditions(backup.tag, share.idx);
		const ciphertext = Buffer.from(share.shareEncrypted.slice(2), 'hex');
		const decodedShare = await decryptToString(
			{
				unifiedAccessControlConditions,
				chain: 'sepolia',
				ciphertext: ciphertext.toString('base64'),
				dataToEncryptHash: share.shareEncryptedHash.slice(2),
				sessionSigs,
			},
			$web3.litClient,
		);
		const secret = await $web3.bukitupClient.decryptShare(decodedShare, privateKey.value);

		await $web3.disconnectLit();

		if (saveType === 'copy') {
			copyToClipboard(secret);
		} else if (saveType === 'restore') {
			$appstate.value.shareToRestore = secret;
			$router.push({ name: 'backup_restore' });
		} else {
			const blob = new Blob([secret], { type: 'text/plain' });
			const url = URL.createObjectURL(blob);
			const a = document.createElement('a');
			a.href = url;

			const now = new Date();
			const yyyy = now.getFullYear();
			const mm = String(now.getMonth() + 1).padStart(2, '0');
			const dd = String(now.getDate()).padStart(2, '0');
			const datePart = `${yyyy}_${mm}_${dd}`;
			a.download = `${backup.tag}_share_${idx + 1}_${datePart}.data`;
			document.body.appendChild(a);
			a.click();
			document.body.removeChild(a);
			URL.revokeObjectURL(url);
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
	$loader.hide();
};
</script>
