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

	<div class="px-3 w-100 mb-3 mt-3" v-if="mode === 'manual' && !sessionId">
		<div class="text-center fw-bold text-secondary mt-2 mb-2">Enter invitation</div>

		<div class="d-flex justify-content-center">
			<input type="text" class="form-control text-center" v-model="invitationString" />
		</div>

		<button class="btn btn-outline-dark w-100 mt-3" @click="joinInvite()" :disabled="!invitationString">Next</button>
	</div>

	<div class="px-3 w-100 mb-3 mt-3" v-if="sessionId && authCode">
		<div class="text-center fw-bold text-secondary mt-2 mb-3">Notify auth code to host device</div>

		<div class="d-flex justify-content-center align-items-center _pointer">
			<span class="fw-bold fs-1">{{ authCode }}</span>
		</div>
	</div>
	<div class="text-center fw-bold text-secondary mt-3 mb-2" v-if="approving">Awaiting approval...</div>
	<div class="text-center fw-bold text-secondary mt-3 mb-2" v-if="syncing">Creating PassKey...</div>
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
import { ref, onMounted, inject, onBeforeUnmount, onUnmounted } from 'vue';
import QrScanner from 'qr-scanner';
import Peer from 'simple-peer';
//import { inflate } from 'pako';

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
const syncing = ref();
const approving = ref();

const invitationString = ref();
const authCode = ref();
const signal = ref();
const sessionId = ref();
let peer, socket;

onMounted(async () => {
	console.log($route.query);
	if ($route.query.sessionId) {
		sessionId.value = $route.query.sessionId;
		$router.replace({ query: {} });
		if (sessionId.value) {
			mode.value = 'manual';
			joinInvite();
		}
	} else {
		useQr();
	}
});

onUnmounted(async () => {
	reset();
});

const useQr = async () => {
	mode.value = 'qr';
	startScan();
};

const reset = async () => {
	if (socket) {
		socket.close();
		socket = null;
	}
	if (peer) {
		peer.destroy();
		peer = null;
	}
	if (qrScanner.value) {
		await qrScanner.value.stop();
		scanning.value = false;
	}
	invitationString.value = null;
	mode.value = null;
	approving.value = null;
	syncing.value = null;
	sessionId.value = null;
	authCode.value = null;
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

const generateAuthCode = () => {
	return Math.random().toString().slice(2, 8);
};

const joinInvite = async () => {
	if (invitationString.value && !sessionId.value) {
		sessionId.value = new URL(invitationString.value).searchParams.get('sessionId');
	}

	if (!sessionId.value) return;

	console.log('sessionId.value', sessionId.value);

	authCode.value = generateAuthCode();

	socket = new WebSocket(CONNECTOR_URL);
	//socket = new WebSocket('ws://localhost:3953');

	socket.onopen = () => {
		console.log('📡 socket.onopen');

		peer = new Peer({
			initiator: false,
			trickle: true,
			config: {
				iceServers: [
					{
						urls: ['turn:135.181.151.155:3954?transport=udp'],
						username: 'test',
						credential: 'test',
					},
					{
						urls: ['stun:135.181.151.155:3955'],
					},
				],
			},
		});

		socket.send(JSON.stringify({ sessionId: sessionId.value, role: 'guest', ready: true }));

		peer.on('signal', (signal) => {
			console.log('📡 Sending answer to signaling server');
			socket.send(JSON.stringify({ sessionId: sessionId.value, role: 'guest', signal }));
		});

		peer.on('connect', () => {
			console.log('✅ Guest connected to host');
			peer.send(JSON.stringify({ type: 'auth-request', authCode: authCode.value }));
			approving.value = true;
		});

		peer.on('data', async (data) => {
			console.log('📩 Guest received:', data.toString());
			const msg = JSON.parse(data);
			if (msg.encryptedKey) {
				console.log('📩 Guest received privateKey:', msg.encryptedKey);

				await syncAccount(msg);
			}
		});

		socket.onmessage = (event) => {
			console.log('📡 socket.onmessage');
			const msg = JSON.parse(event.data);
			if (msg.signal) {
				console.log('📡 Guest received offer from host');
				peer.signal(msg.signal);
			}
		};
	};
};

const syncAccount = async (data) => {
	if (syncing.value) return;
	$loader.show();
	syncing.value = true;
	try {
		const privateKey = $enigma.decryptDataSync(data.encryptedKey, authCode.value);

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
				syncing.value = false;
				return;
			}

			$user.account = account;
			$loader.show();
			await $encryptionManager.createVault({
				keyOptions: {
					username: data.name,
					displayName: data.name,
				},
				address: account.address,
				publicKey: account.publicKey,
				avatar: data.avatar,
				notes: data.notes,
			});

			await $encryptionManager.setData($user.toVaultFormat());

			$user.openStorage();

			if (qrScanner.value && scanning.value) {
				await qrScanner.value.stop();
				scanning.value = false;
			}

			peer.send(JSON.stringify({ success: true }));

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
	syncing.value = false;
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
						sessionId.value = new URL(invitationString.value).searchParams.get('sessionId');
						if (sessionId.value) {
							joinInvite();
							await qrScanner.value.stop();
							scanning.value = false;
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
