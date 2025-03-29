<template>
	<FullContentBlock v-if="$user.account">
		<template #header> <div class="fw-bold fs-5 py-1">New backup</div> </template>
		<template #content>
			<div class="_full_width_block">
				<Account_Activate_Reminder />

				<template v-if="$user.accountInfo.registeredMetaWallet">
					<template v-if="tx?.status !== 'PROCESSING'">
						<div class="_divider mb-3">
							Backup info
							<InfoTooltip class="align-self-center ms-2" :content="'Prepare your backup info'" />
						</div>

						<div class="_input_block mb-3">
							<div class="mb-2">
								<label class="form-label d-flex justify-content-between align-items-center" for="comment">
									<div class="d-flex align-items-center">
										Note
										<InfoTooltip class="align-self-center ms-2" :content="'Notes info'" />
									</div>

									<div class="d-flex justify-content-end align-items-center">
										<div class="form-check form-switch">
											<input class="form-check-input" type="checkbox" role="switch" id="advanced" v-model="advanced" />
											<label class="form-check-label d-flex align-items-center _pointer" for="advanced">
												Advanced
												<InfoTooltip class="align-self-center ms-2" :content="'Advanced mode'" />
											</label>
										</div>
									</div>
								</label>
								<textarea
									type="text"
									id="comment"
									v-model="comment"
									class="form-control"
									:placeholder="`any notes about your backup as purpose reminder, visible only to you, optional, ${maxCommentLength} characters max`"
									rows="2"
								></textarea>
							</div>
							<div class="">
								<div class="d-flex justify-content-between align-items-center" :class="{ 'mb-2': advanced }">
									<label class="form-label d-flex align-items-center mb-0" for="tag">
										Unique tag
										<InfoTooltip class="align-self-center ms-2" :content="'Name info'" />
										<span class="small ms-2 text-secondary" v-if="advanced && tag && maxTagLength > tag.length && tag.length > maxTagLength - 5"
											>{{ maxTagLength - tag.length }} characters left</span
										>
										<span class="small ms-2 text-secondary" v-if="advanced && !tag">{{ maxTagLength }} characters max</span>
									</label>

									<div class="d-flex align-items-center">
										<div class="fw-bold text-primary" v-if="!advanced">
											{{ tag }}
										</div>

										<i class="_icon_reload bg-black ms-3 _pointer" @click="generateTag(10)"></i>
										<i class="_icon_copy bg-black ms-3 _pointer" @click="copyToClipboard(tag)" v-if="tag"></i>
									</div>
								</div>

								<div class="d-flex" v-if="advanced">
									<input
										type="text"
										id="tag"
										v-model="tag"
										class="form-control"
										placeholder="unique name of your backup"
										:class="[tagDirty && (tagInvalid ? 'is-invalid' : 'is-valid')]"
									/>
									<button class="btn btn-dark ms-2 d-flex align-items-center" @click="generateTag(10)">
										<i class="_icon_reload bg-white"></i>
										<span class="ms-2" v-if="$breakpoint.gt('md')">Generate</span>
									</button>
								</div>

								<div class="small text-danger" v-if="tagDirty && tagInvalid">
									{{ tagInvalid }}
								</div>
							</div>

							<div class="mb-2 mt-2" v-if="advanced">
								<label class="form-label d-flex align-items-center" for="secret">
									Private data
									<InfoTooltip class="align-self-center ms-2" :content="'Private data info'" />
									<span class="small ms-2 text-secondary" v-if="secret && maxSecretLength > secret.length">{{ maxSecretLength - secret.length }} characters left</span>
									<span class="small ms-2 text-secondary" v-if="!secret">{{ maxSecretLength }} characters max</span>
								</label>
								<textarea
									type="text"
									id="secret"
									v-model="secret"
									class="form-control"
									placeholder="any data you want to share with trusted parties"
									rows="3"
									:class="[secretDirty && (secretInvalid ? 'is-invalid' : 'is-valid')]"
								></textarea>
								<div class="invalid-feedback">
									{{ secretInvalid }}
								</div>
							</div>
						</div>

						<div class="_divider mb-3">
							Trusted parties
							<InfoTooltip class="align-self-center ms-2" :content="'Add trusted parties info'" />
						</div>

						<div class="_input_block mb-2" v-for="(wallet, idx) in wallets">
							<TrustedParty_Item :wallet="wallet" :data="{ length: wallets.length, wallets, idx, advanced }" @set-wallet="setWallet" @remove-wallet="() => wallets.splice(idx, 1)" />
						</div>

						<div class="mb-3" v-if="wallets.length > 1 && advanced">
							<label class="form-label d-flex align-items-center" for="treshold">
								Restore treshold
								<InfoTooltip class="align-self-center ms-2" :content="'Restore treshold info'" />
								<span class="small ms-2 text-secondary"></span>
							</label>
							<input type="number" id="treshold" v-model="treshold" min="1" :max="wallets.length" class="form-control" placeholder="minimal number of parties to recover secret" />
						</div>

						<div class="row justify-content-center gx-2 mb-2 mt-3">
							<div class="col-lg-12 col-xl-10 mb-2">
								<button type="button" class="btn btn-dark w-100" @click="addPartiesFromContacts()">Add from contacts</button>
							</div>
							<div class="col-lg-12 col-xl-10 mb-2" v-if="advanced">
								<button type="button" class="btn btn-dark w-100" @click="addPartiesManually()">Add manually</button>
							</div>
						</div>

						<div class="small mb-2 text-danger text-center" v-if="wallets.length && walletsNumberInvalid">Min 4 trusted parties required. To use less switch to advanced mode</div>

						<template v-if="wallets.length && !advanced">
							<div class="_divider mb-3">
								Set restore delay
								<InfoTooltip class="align-self-center ms-2" :content="'Submit transaction info'" />
							</div>

							<div class="row justify-content-center gx-2">
								<div class="col-lg-12 col-xl-10 mb-2">
									<div class="dropdown">
										<button class="btn btn-dark dropdown-toggle w-100" type="button" data-bs-toggle="dropdown" aria-expanded="false">
											{{ commonDelay > 0 ? $filters.secondsToHMS(commonDelay) : 'No delay' }}
										</button>
										<ul class="dropdown-menu">
											<li v-for="delay in delays">
												<a class="dropdown-item" href="#" @click="commonDelay = delay">
													{{ delay > 0 ? $filters.secondsToHMS(delay) : 'No delay' }}
												</a>
											</li>
										</ul>
									</div>
								</div>
							</div>
						</template>

						<template v-if="wallets.length && !isInvalid">
							<div class="_divider mb-3">
								Submit transaction
								<InfoTooltip class="align-self-center ms-2" :content="'Submit transaction info'" />
							</div>

							<div class="row justify-content-center gx-2">
								<div class="col-lg-12 col-xl-10 mb-2">
									<button type="button" class="btn btn-dark w-100" @click="backup()" :disabled="tx?.status === 'PROCESSING' || walletsNumberInvalid">Create</button>
								</div>
							</div>
						</template>
					</template>

					<div class="text-center fw-bold fs-3" v-if="tx?.status === 'PROCESSING'">Creating Backup ...</div>

					<div :class="[tx && submitted ? '_input_block mt-2' : 'd-none']">
						<div class="small mb-2">Latest transaction</div>
						<Transactions :list="tx ? [tx] : null" only-last="true" />
					</div>
				</template>
			</div>
		</template>
	</FullContentBlock>
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
._full_width_block {
	max-width: 40rem;
	width: 100%;
}
</style>

<script setup>
import TrustedParty_Item from './Backup_TrustedParty_Item.vue';
import Account_Activate_Reminder from '@/components/Account_Activate_Reminder.vue';
import { ref, onMounted, watch, inject, computed, nextTick, onUnmounted } from 'vue';
import copyToClipboard from '@/utils/copyToClipboard';
import { encryptString } from '@lit-protocol/encryption';
import { encryptWithPublicKey, cipher } from 'eth-crypto';
import axios from 'axios';
import FullContentBlock from '@/components/FullContentBlock.vue';
import Transactions from '@/views/account/Transactions.vue';
import { uploadToIPFS } from '../../api/ipfs';
import { Wallet, utils } from 'ethers';

const $user = inject('$user');
const $timestamp = inject('$timestamp');
const $web3 = inject('$web3');
const $swal = inject('$swal');
const $mitt = inject('$mitt');
const $socket = inject('$socket');
const $loader = inject('$loader');
const $modal = inject('$modal');
const $swalModal = inject('$swalModal');
const $route = inject('$route');

const maxTagLength = 30;
const maxSecretLength = 500;
const maxCommentLength = 200;

const advanced = ref();
const tag = ref();
const delays = [0, 600, 3600, 86400, 259200, 604800, 1296000, 2592000];
const commonDelay = ref(259200);
const wallets = ref([]);

const secret = ref();
const comment = ref();
const submitted = ref();

const tagDirty = ref();
const secretDirty = ref();

watch(
	() => advanced.value,
	(newValue) => {
		//generateTag();
		///comment.value = null;
		treshold.value = wallets.value.length;
		//for (let i = 0; i < wallets.value.length; i++) {
		//	//wallets.value[i].message = null;
		//	//wallets.value[i].delay = 259200;
		//}
	},
);

watch(
	() => tag.value,
	(newValue) => {
		tagDirty.value = true;
		if (newValue && newValue.length > maxTagLength) {
			tag.value = newValue.slice(0, maxTagLength);
		}
	},
);

const tagInvalid = computed(() => {
	if (!tag.value) return 'Tag is required';
});

watch(
	() => secret.value,
	(newValue) => {
		secretDirty.value = true;
		if (newValue && newValue.length > maxSecretLength) {
			secret.value = newValue.slice(0, maxSecretLength);
		}
		submitted.value = false;
	},
);

watch(
	() => comment.value,
	(newValue) => {
		if (newValue && newValue.length > maxCommentLength) {
			comment.value = newValue.slice(0, maxCommentLength);
		}
	},
);

const treshold = ref(1);
watch(
	() => treshold.value,
	(newValue) => {
		if (newValue && newValue > wallets.value.length) {
			treshold.value = wallets.value.length;
		}
	},
);

const backupAccount = () => {
	const backup = {
		account: {
			name: $user.accountInfo.name,
			address: $user.account.address,
			publicKey: $user.account.publicKey,
			privateKey: $user.account.privateKey,
			notes: $user.accountInfo.notes,
			avatar: $user.accountInfo.avatar,
		},
	};
	comment.value = 'My Account Backup';
	secret.value = JSON.stringify(backup);
};

const tx = computed(() => {
	const txs = $user.transactions.filter((t) => t.method === 'addBackup');
	return txs.length ? txs[0] : null;
});

watch(
	() => tx.value,
	(tx) => {
		if (tx) {
			if (tag.value?.trim() === tx.methodData.tag && tx.status === 'PROCESSED') {
				$swal.fire({
					icon: 'success',
					title: 'Backup created',
					timer: 5000,
				});
				reset();
				backupAccount();
			}
		}
	},
);

const setWallet = async (data) => {
	data.wallet.dirty = true;
	wallets.value[data.idx] = data.wallet;
	checkWallets();
};

const checkWallets = async () => {
	for (let i = 0; i < wallets.value.length; i++) {
		wallets.value[i].dirty = true;

		const wallet = wallets.value[i];
		if (!wallet.address) {
			wallets.value[i].invalid = 'Address is required';
			continue;
		}

		if (!utils.isAddress(wallet.address)) {
			wallets.value[i].invalid = 'Address not valid';
			continue;
		}

		if (!wallet.metaPublicKey) {
			try {
				const metaPublicKey = await $web3.registryContract.metaPublicKeys(wallet.address);
				if (!metaPublicKey || metaPublicKey.length <= 2) {
					wallets.value[i].invalid = 'Meta address not registered for this wallet';
					continue;
				}
				wallets.value[i].metaPublicKey = metaPublicKey;
			} catch (error) {
				console.log(error);
				wallets.value[i].invalid = 'Error checking meta address';
				continue;
			}
		}
		wallets.value[i].invalid = false;
	}
};

watch(
	() => wallets.value.length,
	async (newValue, oldValue) => {
		if (newValue) {
			if (!treshold.value || treshold.value > newValue) treshold.value = newValue;
		} else {
			treshold.value = newValue;
		}
	},
);

const addPartiesFromContacts = async () => {
	$modal.value.open({
		id: 'contacts',
		excluded: wallets.value.map((w) => w.address),
		metaRequired: true,
	});
};

const applyPartiesFromContacts = async (addresses) => {
	wallets.value.push(...addresses.map((a) => ({ address: a, dirty: true, delay: 259200 })));
	checkWallets();
};

const addPartiesManually = () => {
	wallets.value.push({
		address: null,
		stealth: null,
		message: null,
		delay: 0,
		valid: false,
	});
};

onMounted(async () => {
	if (!$user.accountInfo.registeredMetaWallet) {
	}
	generateTag();
	$socket.on('BACKUP_UPDATE', updateData);
	$mitt.on('contacts::selected', applyPartiesFromContacts);
	backupAccount();
});

onUnmounted(async () => {
	$socket.off('BACKUP_UPDATE', updateData);
	$mitt.off('contacts::selected', applyPartiesFromContacts);
});

const updateData = async (tagUpdate) => {
	if (tag.value?.trim() === tagUpdate) {
		// reset()
	}
};

const secretInvalid = computed(() => {
	if (!secret.value?.trim()) return 'Secret is required';
});

const walletsNumberInvalid = computed(() => {
	if (!advanced.value && wallets.value.length < 4) return 'Secret is required';
});

const walletsInvalid = computed(() => {
	if (wallets.value.find((w) => w.invalid)) return true;
});

const tresholdInvalid = computed(() => {
	if (treshold.value < 1) return 'Must be > 1';
	if (treshold.value > wallets.value.length) return 'Must be less or equal to wallets number';
});

const isInvalid = computed(() => {
	if (secretInvalid.value) return true;
	if (tagInvalid.value) return true;
	if (tresholdInvalid.value) return true;
	if (walletsInvalid.value) return true;
});

const reset = () => {
	wallets.value = [];
	secret.value = null;
	comment.value = null;
	tag.value = null;
	treshold.value = 1;
	//submitted.value = false
	advanced.value = false;
	generateTag();
	nextTick(() => {
		secretDirty.value = false;
		tagDirty.value = false;
	});
};

const backup = async () => {
	await checkWallets();
	if (isInvalid.value) return;

	if (
		!(await $swalModal.value.open({
			id: 'confirm',
			title: 'Backup creation',
			content: 'Confirm transaction',
		}))
	)
		return;

	try {
		$loader.show();

		let commentEncrypted = await encryptWithPublicKey($user.account.metaPublicKey.slice(2), comment.value || '');

		const backup = {
			owner: $user.account.address,
			disabled: 0,
			treshold: treshold.value,
			commentEncrypted: '0x' + cipher.stringify(commentEncrypted),
			shares: [],
		};
		const stealthPublicKeys = [];

		for (const wallet of wallets.value) {
			const SA = $web3.bukitupClient.generateStealthAddress(wallet.metaPublicKey);
			stealthPublicKeys.push(SA.publicKey);

			const messageEncrypted = await encryptWithPublicKey(SA.publicKey.slice(2), wallet.message || '');
			const addressEncrypted = await encryptWithPublicKey($user.account.metaPublicKey.slice(2), wallet.address);

			const delay = advanced.value ? wallet.delay || 0 : commonDelay.value;

			backup.shares.push({
				stealthAddress: SA.address,
				messageEncrypted: '0x' + cipher.stringify(messageEncrypted),
				addressEncrypted: '0x' + cipher.stringify(addressEncrypted),
				ephemeralPubKey: SA.ephemeralPubKey,
				shareEncrypted: '0x',
				shareEncryptedHash: '0x',
				delay,
				request: 0,
				disabled: 0,
			});
		}

		try {
			const d = JSON.parse(secret.value);
			if (d.account && d.account.publicKey === $user.account.publicKey) {
				const offchainBkp = {
					accountInfo: $user.accountInfo || {},
					contacts: $user.contacts || [],
				};
				let offchainBkpEncrypted = await encryptWithPublicKey($user.account.publicKey.slice(2), JSON.stringify(offchainBkp));
				const cid = await uploadToIPFS(cipher.stringify(offchainBkpEncrypted));
				d.offchain = cid;
				secret.value = JSON.stringify(d);
			}
		} catch (error) {
			console.log(error);
		}

		const shares = await $web3.bukitupClient.generateSharesEncrypted(secret.value, stealthPublicKeys.length, treshold.value, stealthPublicKeys);

		const sessionSig = await $web3.getSessionSigs(new Wallet($user.account.privateKey));
		if (!sessionSig) {
			return $loader.hide();
		}

		for (let i = 0; i < shares.length; i++) {
			const share = shares[i];
			const unifiedAccessControlConditions = $web3.getAccessControlConditions(tag.value, i);
			const litEncrypted = await encryptString({ unifiedAccessControlConditions, dataToEncrypt: share }, $web3.litClient);
			backup.shares[i].shareEncrypted += Buffer.from(litEncrypted.ciphertext, 'base64').toString('hex');
			backup.shares[i].shareEncryptedHash += litEncrypted.dataToEncryptHash;
		}

		console.log('backup', backup);

		const expire = $timestamp.value + 300;
		const domain = {
			name: 'BuckitUpVault',
			version: '1',
			chainId: $web3.mainChainId,
			verifyingContract: $web3.bc.vault.address,
		};
		const types = {
			Share: [
				{ name: 'stealthAddress', type: 'address' },
				{ name: 'messageEncrypted', type: 'bytes' },
				{ name: 'addressEncrypted', type: 'bytes' },
				{ name: 'ephemeralPubKey', type: 'bytes' },
				{ name: 'shareEncrypted', type: 'bytes' },
				{ name: 'shareEncryptedHash', type: 'bytes' },
				{ name: 'delay', type: 'uint40' },
				{ name: 'request', type: 'uint40' },
				{ name: 'disabled', type: 'uint8' },
			],
			Backup: [
				{ name: 'owner', type: 'address' },
				{ name: 'disabled', type: 'uint8' },
				{ name: 'treshold', type: 'uint8' },
				{ name: 'commentEncrypted', type: 'bytes' },
				{ name: 'shares', type: 'Share[]' },
			],
			AddBackup: [
				{ name: 'tag', type: 'string' },
				{ name: 'backup', type: 'Backup' },
				{ name: 'expire', type: 'uint40' },
			],
		};
		const message = {
			tag: tag.value,
			backup,
			expire,
		};
		const signature = await $web3.signTypedData($user.account.privateKey, domain, types, message);

		await axios.post(API_URL + '/dispatch/addBackup', {
			wallet: $user.account.address,
			chainId: $web3.mainChainId,
			tag: tag.value,
			backup,
			expire,
			signature,
		});
		submitted.value = true;

		$swal.fire({
			icon: 'success',
			title: 'Backup',
			footer: 'Please wait for transaction confirmation',
			timer: 5000,
		});
	} catch (error) {
		console.log(error);
		$swal.fire({
			icon: 'error',
			title: 'Backup error',
			footer: error.toString(),
			timer: 30000,
		});
	}
	$loader.hide();
};

function generateTag(l = 10) {
	const BASE62_CHARS = '0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
	let t = '';
	for (let i = 0; i < l; i++) {
		const randomIndex = crypto.getRandomValues(new Uint8Array(1))[0] % BASE62_CHARS.length;
		t += BASE62_CHARS[randomIndex];
	}
	tag.value = t;
}
</script>
