<template>
	<div class="text-center text-secondary mt-3 mb-3 px-3">
		Scan this QR code with your phone camera and follow by the link or open BuckitUp application and on login screen select "Sync with other device"
	</div>

	<div class="_qrh_wrapper mb-3">
		<div class="_qrh_container">
			<canvas ref="qrCode"></canvas>
		</div>
	</div>

	<div class="px-3 mb-3 d-flex justify-content-center align-items-center">
		<button class="btn btn-outline-dark d-flex justify-content-center align-items-center px-4" @click="copyInvite()" :disabled="!qrString">
			Copy invite link <i class="_icon_copy bg-black ms-2"></i>
		</button>
	</div>

	<div class="d-flex justify-content-center align-items-center flex-column mt-2 mb-3" v-if="authCode">
		<div class="text-secondary">Enter auth code when it prompts</div>

		<div class="d-flex justify-content-center align-items-center _pointer" @click="copyToClipboard(authCode)">
			<span class="fw-bold fs-1">{{ authCode }}</span>
			<i class="_icon_copy bg-black ms-2"></i>
		</div>
	</div>

	<div class="text-center">
		<a href="#" @click.prevent="getInvite()" v-if="qrString">{{ qrString ? 'Generate new' : '' }}</a>
		<span class="text-secondary" v-else>Generating invite...</span>
	</div>

	<div class="text-center mt-2 mb-3" v-if="false">
		<div class="fw-bold text-secondary">Enter decrypt code on second device to sync</div>
		<div class="d-flex justify-content-center align-items-center _pointer px-4" @click="copyToClipboard(encryptionKey)">
			<span class="fw-bold fs-3 _truncate">{{ encryptionKey }}</span>
			<i class="_icon_copy bg-black ms-2"></i>
		</div>
	</div>
</template>

<style lang="scss">
@import '@/scss/variables.scss';

._qrh_wrapper {
	display: flex;
	justify-content: center;

	position: relative;
	._generating {
		position: absolute;
	}
	._qrh_container {
		width: 100% !important;
		max-width: 300px !important;
		display: flex;
		justify-content: center;
		canvas {
			width: 100% !important;
			height: auto !important;
		}
	}
}
</style>

<script setup>
import { ref, onMounted, watch, inject } from 'vue';
import copyToClipboard from '@/utils/copyToClipboard';
import QRCode from 'qrcode';

const qrCode = ref(); //
const $user = inject('$user');
const $enigma = inject('$enigma');

const authCode = ref();
const encryptionKey = ref();
const qrString = ref();
const showAuthCode = ref();
const mode = ref();

onMounted(async () => {
	getInvite();
});

watch(
	() => qrString.value,
	(newVal) => {
		if (newVal) {
			QRCode.toCanvas(qrCode.value, newVal, {
				errorCorrectionLevel: 'M',
				height: 360,
				width: 360,
				quality: 1,
				margin: 0,
			});
		}
	},
);

const copyInvite = () => {
	copyToClipboard(`${location.origin}/login?encryptionKey=${encodeURIComponent(encryptionKey.value)}`);
	mode.value = 'manual';
};

const getInvite = () => {
	qrString.value = null;
	mode.value = null;
	authCode.value = $enigma.generateSecurePassword(6); //
	encryptionKey.value = $enigma.encryptDataSync($user.account.privateKey, authCode.value);
	qrString.value = `${location.origin}/login?encryptionKey=${encodeURIComponent(encryptionKey.value)}&authCode=${encodeURIComponent(authCode.value)}`;
	showAuthCode.value = true;
};
</script>
