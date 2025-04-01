<template>
	<!-- Header -->

	<div class="_main">
		<div class="_img">
			<img :src="`/img/activation_1.png`" alt="" v-show="step == 1" />
			<img :src="`/img/activation_2.png`" alt="" v-show="step == 2" />
			<img :src="`/img/activation_1.png`" alt="" v-show="step == 3" />
			<img :src="`/img/activation_2.png`" alt="" v-show="step == 4" />
		</div>

		<div class="btn _icon_times bg-dark" @click="closeModal()"></div>

		<div class="_content p-4">
			<div class="fs-3 fw-bold mb-3">
				<span v-if="step == 1"> Activate Your Profile & Unlock the Features </span>
				<span v-if="step == 2"> Share & Secure with Backup Community Key </span>
				<span v-if="step == 3"> Seamless Transactions with FluidKey Wallet </span>
				<span v-if="step == 4"> Explore the Power of Gnosis Blockchain </span>
			</div>

			<div class="text-secondary mb-3 _text">
				<span v-if="step == 1">
					Secure your profile by activating essential features like backup community key sharing, support for Gnosis blockchain applications. Take full control of your digital assets and
					interactions with ease.
				</span>
				<span v-if="step == 2">
					Enhance security by enabling a backup key shared within your trusted community. This ensures access to your profile even in unforeseen circumstances, giving you peace of mind.
				</span>
				<span v-if="step == 3">
					Integrate your FluidKey Wallet to manage digital assets effortlessly. Benefit from a fast, secure, and user-friendly wallet experience tailored to your blockchain needs.
				</span>
				<span v-if="step == 4">
					Activate Gnosis blockchain features to access a range of applications designed for secure, decentralized operations. From smart contracts to advanced tools, elevate your profile's
					capabilities.
				</span>
			</div>

			<div class="d-flex justify-content-between align-items-center mb-4">
				<div>
					<button class="btn btn-primary rounded-pill p-3 me-2" @click="step == 1 ? (step = 4) : step--">
						<i class="_icon_arrow_left bg-white opacity-75"></i>
					</button>
					<button class="btn btn-primary rounded-pill p-3 me-2" @click="step == 4 ? (step = 1) : step++">
						<i class="_icon_arrow_right bg-white opacity-75"></i>
					</button>
				</div>

				<div class="_steps">
					<div v-for="s in steps" :class="{ _active: step == s }" @click="step = s"></div>
				</div>
			</div>

			<div class="form-check form-switch mb-3">
				<input class="form-check-input" type="checkbox" role="switch" id="setpassword" v-model="agree" />
				<label class="form-check-label d-flex align-items-center _pointer" for="setpassword">
					I agree with
					<a href="#" class="ms-1">terms and conditions</a>
				</label>
			</div>

			<div class="d-flex justify-content-center mt-2">
				<button class="btn btn-dark w-100" @click="register()" :disabled="!agree || processingTx">Activate</button>
			</div>

			<div :class="[processingTx ? '_input_block mt-2' : 'd-none']">
				<div class="small mb-2">Latest transaction</div>
				<Transactions :list="processingTx ? [processingTx] : null" only-last="true" />
			</div>
		</div>
	</div>
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
._main {
	position: relative;
	._text {
		min-height: 8rem;
	}
	._steps {
		display: flex;
		div {
			margin: 0.2rem;
			height: 6px;
			width: 1.6rem;
			border-radius: 3rem;
			background-color: $grey_dark;
			cursor: pointer;
			&._active {
				background-color: $primary;
				width: 3rem;
			}
		}
	}
	._icon_times {
		position: absolute;
		top: 20px;
		right: 20px;
	}
	._content {
		margin-top: -8rem; /* Adjust this value visually */
		padding-top: 8rem; /* Ensure enough spacing */
		position: relative; /* Keep text on top */
	}
	._img {
		display: flex;
		justify-content: center;
		align-items: center;
		width: 100%; /* Full width */
		max-height: 20rem; /* Maximum height */
		overflow: hidden; /* Hide overflow */
		position: relative;
		border-top-left-radius: $blockRadius;
		border-top-right-radius: $blockRadius;
		img {
			width: 100%; /* Ensure full width */
			height: 100%; /* Fill height */
			max-height: 20rem; /* Prevent going beyond 30rem */
			object-fit: cover; /* Crop to fit without distortion */
			object-position: top;
		}
		&::after {
			content: '';
			position: absolute;
			bottom: 0;
			left: 0;
			width: 100%;
			height: 80%; /* Half the height of the container */
			background: linear-gradient(to bottom, rgba(255, 255, 255, 0) 0%, white 100%);
		}
	}
}
</style>

<script setup>
import { ref, inject, watch, onMounted, onUnmounted } from 'vue';
import Transactions from '@/views/account/Transactions.vue';
import axios from 'axios';
import errorMessage from '@/utils/errorMessage';

const $mitt = inject('$mitt');
const $user = inject('$user');
const $timestamp = inject('$timestamp');
const $web3 = inject('$web3');
const $swal = inject('$swal');
const $loader = inject('$loader');
const $socket = inject('$socket');

const steps = [1, 2, 3, 4];
const step = ref(1);
const agree = ref();
const processingTx = ref();

onMounted(async () => {
	$socket.on('DISPATCH', dispatchListener);
	$socket.on('WALLET_UPDATE', walletUpdateListener);
});

onUnmounted(async () => {
	$socket.off('WALLET_UPDATE', walletUpdateListener);
	$socket.off('DISPATCH', dispatchListener);
});

const dispatchListener = async (tx) => {
	if ($user.account?.address?.toLowerCase() === tx.wallet.toLowerCase() && tx.method === 'registerWithSign') {
		processingTx.value = tx;
	}
};

const walletUpdateListener = async (wallet) => {
	if ($user.account?.address?.toLowerCase() === wallet.toLowerCase()) {
		$user.checkMetaWallet();
	}
};

watch(
	() => $user.registeredMetaWallet,
	(newVal) => {
		if (newVal) {
			closeModal();
			$swal.fire({
				icon: 'success',
				title: 'Account activated',
				timer: 5000,
			});
		}
	},
);

const register = async () => {
	if (!$user.checkOnline()) return;
	try {
		$loader.show();

		const expire = $timestamp.value + 300000;
		const domain = {
			name: 'BuckitUpRegistry',
			version: '1',
			chainId: $web3.mainChainId,
			verifyingContract: $web3.bc.registry.address,
		};
		const types = {
			RegisterWithSign: [
				{ name: 'owner', type: 'address' },
				{ name: 'metaPublicKey', type: 'bytes' },
				{ name: 'expire', type: 'uint40' },
			],
		};
		const message = {
			owner: $user.account.address,
			metaPublicKey: $user.account.metaPublicKey,
			expire,
		};
		const signature = await $web3.signTypedData($user.account.privateKey, domain, types, message);

		await axios.post(API_URL + '/dispatch/register', {
			owner: $user.account.address,
			chainId: $web3.mainChainId,
			metaPublicKey: $user.account.metaPublicKey,
			expire: expire,
			signature: signature,
		});

		$swal.fire({
			icon: 'success',
			title: 'Register',
			footer: 'Please wait for transaction confirmation',
			timer: 5000,
		});
	} catch (error) {
		console.error(error);
		$swal.fire({
			icon: 'error',
			title: 'Register error',
			text: errorMessage(error),
			timer: 15000,
		});
	}
	$loader.hide();
};

defineExpose({ register });

function closeModal() {
	$mitt.emit('modal::close');
}
</script>
