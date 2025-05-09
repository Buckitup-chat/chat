<template>
	<div class="px-3 mb-2 mt-2" v-if="mode !== 'qr'">
		<button class="btn btn-outline-dark w-100 mt-3" @click="useQr()">Scan QR code on second device</button>
	</div>

	<div v-show="scanning">
		<div class="text-center fw-bold text-secondary mt-3 mb-2">Scan QR code on second device to establish automatic connection</div>
		<div class="_qr_scanner">
			<video ref="qrScannerEl"></video>
		</div>
	</div>

	<div class="px-3 mb-2 mt-2" v-if="mode !== 'manual'">
		<button class="btn btn-outline-dark w-100 mt-3" @click="useManual()">Enter invitation manually</button>
	</div>

	<div class="px-3 w-100 mb-3 mt-3" v-if="mode === 'manual' && !encryptionKey">
		<div class="text-center fw-bold text-secondary mt-2 mb-2">Enter invitation</div>

		<div class="d-flex justify-content-center">
			<input type="text" class="form-control text-center" v-model="invitationString" />
		</div>

		<button class="btn btn-outline-dark w-100 mt-3" @click="joinInvite()" :disabled="!invitationString">Next</button>
	</div>

	<div class="px-3 w-100 mb-3 mt-3" v-if="encryptionKey && !authenticated">
		<div class="text-center fw-bold text-secondary mt-2 mb-3">Enter auth code from first device</div>

		<div class="d-flex justify-content-center">
			<input type="text" class="form-control _code_input" v-model="authCode" @keydown.enter="authenticate()" />
		</div>

		<button class="btn btn-outline-dark w-100 mt-3" @click="authenticate()" :disabled="!authCode || isWaitingForSpace">Authenticate</button>
	</div>

	<div class="text-center fw-bold text-secondary mt-3 mb-2" v-if="isWaitingForSpace">Connecting...</div>
	<div class="text-center fw-bold text-secondary mt-3 mb-2" v-if="decrypting">Authenticating...</div>
</template>

<style lang="scss">
@import '@/scss/variables.scss';

._qr_scanner {
	display: flex;
	justify-content: center;
	align-items: center;
	border-radius: 1rem;
	overflow: hidden;
	video {
		width: 100%;
	}
}

._code_input {
	width: 80%;
	height: 50px;
	font-weight: 500;
	font-size: 40px;
	text-align: center;
}
</style>

<script setup>
import { ref, onMounted, inject } from 'vue';
import QrScanner from 'qr-scanner';

const qrScannerEl = ref();
const qrScanner = ref();
const hasCamera = ref();

const $route = inject('$route');
const $router = inject('$router');
const $swal = inject('$swal');
const $loader = inject('$loader');
const $mitt = inject('$mitt');
const $user = inject('$user');
const $enigma = inject('$enigma');
const $encryptionManager = inject('$encryptionManager');
const $swalModal = inject('$swalModal');

const mode = ref();

const scanning = ref();
const authenticating = ref();
const authenticated = ref();
const decrypting = ref();

const invitationString = ref();
const uid = ref();
const authCode = ref();
const encryptionKey = ref();

onMounted(async () => {
	if ($route.query.encryptionKey) {
		encryptionKey.value = decodeURIComponent($route.query.encryptionKey);
		mode.value = 'manual';
		$router.replace({ query: {} });
		joinInvite();
	}
});

const useQr = async () => {
	mode.value = 'qr';
	startScan();
};

const useManual = async () => {
	mode.value = 'manual';
	try {
		if (qrScanner.value) {
			await qrScanner.value.stop();
			scanning.value = false;
		}
	} catch (error) {
		console.error('authenticate error', error);
	}
};

const joinInvite = async () => {
	try {
		if (invitationString.value) {
			const params = new URL(invitationString.value).searchParams;
			//uid.value = params.get('uid') || null;
			encryptionKey.value = decodeURIComponent(params.get('encryptionKey')) || null;
			authCode.value = params.get('authCode') || null;
			console.log('🔑 Extracted Invitation', encryptionKey.value, authCode.value);
		}

		if (!encryptionKey.value) {
			console.error('❌ No valid invitation code found.');
			return;
		}
	} catch (error) {
		console.error('authenticate error', error);
		invitationString.value = null;

		encryptionKey.value = null;
		authCode.value = null;
	}
};
//https://localhost:5173/login?encryptionKey=
//lwuMN3m4GUiHNQjZYyDF92dQX8i2fKbqbRpm%2FPGlRrfceoCvc8Qx1MT%2ByZW0zVTB0TGlDQH9q4dzmP%2BUQ4ROg0dN2ZULXnSBFBm7uYnC13PHBDKmMRRsccsW6gGC
//lwuMN3m4GUiHNQjZYyDF92dQX8i2fKbqbRpm/PGlRrfceoCvc8Qx1MT+yZW0zVTB0TGlDQH9q4dzmP+UQ4ROg0dN2ZULXnSBFBm7uYnC13PHBDKmMRRsccsW6gGC
const authenticate = async () => {
	if (authenticating.value || authenticated.value || !authCode.value) return;
	authenticating.value = true;
	try {
		authenticated.value = true;
		await decryptAccount();
	} catch (error) {
		console.error('authenticate error', error);

		space.value = null;
		invitation.value = null;
	}
	authenticating.value = false;
};

const decryptAccount = async () => {
	if (decrypting.value || !encryptionKey.value) return;
	decrypting.value = true;
	console.log('decryptAccount ', encryptionKey.value);
	$loader.show();
	try {
		const privateKey = $enigma.decryptDataSync(encryptionKey.value, authCode.value);
		console.log('decryptAccount account', privateKey);
		const account = await $user.generateAccount(privateKey);
		console.log('decryptAccount account', account);

		if (account) {
			$user.vaults = await $encryptionManager.getVaults();
			const idx = $user.vaults.findIndex((a) => a.publicKey === account.publicKey);

			if (idx > -1) {
				$loader.hide();
				await $swalModal.value.open({
					id: 'confirm',
					title: 'Account sync',
					content: `
						Account <strong>${accountInfo.name}</strong> already present on this device.
						`,
				});
				return;
			}

			$user.account = account;
			await $user.openStorage();

			$loader.show();

			await $encryptionManager.createVault({
				keyOptions: {
					username: $user.accountInfo.name,
					displayName: $user.accountInfo.name,
				},
				address: account.address,
				publicKey: account.publicKey,
				avatar: $user.accountInfo.avatar,
				notes: $user.accountInfo.notes,
			});

			await $encryptionManager.setData($user.toVaultFormat());

			if (qrScanner.value && scanning.value) {
				await qrScanner.value.stop();
				scanning.value = false;
			}

			$mitt.emit('account::created');
			$mitt.emit('modal::close');
			$router.replace({ name: 'account_info' });
			$swal.fire({
				icon: 'success',
				title: 'Device connected',
				timer: 5000,
			});
		}
	} catch (error) {
		console.error('decryptAccount error', error);
		$user.logout();
	}
	decrypting.value = false;
	$loader.hide();
};

const startScan = async () => {
	try {
		const devices = await navigator.mediaDevices.enumerateDevices();
		hasCamera.value = devices.some((device) => device.kind === 'videoinput');

		if (hasCamera.value) {
			qrScanner.value = new QrScanner(
				qrScannerEl.value,
				async (result) => {
					if (!invitationString.value) {
						invitationString.value = result.data;
						await joinInvite();
						if (encryptionKey.value) {
							await qrScanner.value.stop();
							scanning.value = false;
							authenticate();
						}
					}
				},
				{
					returnDetailedScanResult: true,
					preferredCamera: 'environment',
					highlightScanRegion: true,
					highlightCodeOutline: true,
					calculateScanRegion: (video) => {
						const width = video.videoWidth;
						const height = video.videoHeight;
						const scanSize = 0.8; // 100% of video size
						//const size = width > height ? height : width;
						return {
							x: (width * (1 - scanSize)) / 2, // Center horizontally
							y: (height * (1 - scanSize)) / 2, // Center vertically
							width: width * scanSize, // 80% width
							height: height * scanSize, // 80% height
						};
					},
				},
			);

			await qrScanner.value.start();
			scanning.value = true;
		}
	} catch (error) {
		console.error('Error checking camera availability:', error);
	}
};
</script>
