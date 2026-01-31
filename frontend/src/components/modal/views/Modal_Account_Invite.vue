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
		<div class="text-secondary">Guest auth code must mach</div>

		<div class="d-flex justify-content-center align-items-center mb-2">
			<span class="fw-bold fs-1">{{ authCode }}</span>
		</div>

		<button class="btn btn-dark" @click="approveGuest">Approve and connect</button>
	</div>

	<div class="text-center">
		<a href="#" @click.prevent="getInvite()" v-if="qrString">{{ qrString ? 'Generate new' : '' }}</a>
		<span class="text-secondary" v-else>Generating invite...</span>
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
import { ref, onMounted, watch, inject, onUnmounted } from 'vue';
import copyToClipboard from '@/utils/copyToClipboard';
import QRCode from 'qrcode';
import Peer from 'simple-peer';

const qrCode = ref(); //
const $user = inject('$user');
const $enigma = inject('$enigma');
const $swal = inject('$swal');
const $mitt = inject('$mitt');

const authCode = ref();
const qrString = ref();
const mode = ref();

let socket, peer;

onMounted(async () => {
	getInvite();
});

onUnmounted(async () => {
	reset();
});

const reset = async () => {
	if (socket) {
		socket.close();
		socket = null;
	}
	if (peer) {
		peer.destroy();
		peer = null;
	}
	mode.value = null;

	qrString.value = null;
	authCode.value = null;
};

watch(
	() => qrString.value,
	(newVal) => {
		if (newVal) {
			QRCode.toCanvas(qrCode.value, newVal, {
				errorCorrectionLevel: 'L',
				height: 360,
				width: 360,
				quality: 1,
				margin: 0,
			});
		}
	},
);

const copyInvite = () => {
	copyToClipboard(qrString.value);
	mode.value = 'manual';
};

const getInvite = () => {
	qrString.value = null;
	mode.value = null;
	authCode.value = null;

	socket = new WebSocket(CONNECTOR_URL);
	//socket = new WebSocket('ws://localhost:3953');
	const sessionId = crypto.randomUUID();

	socket.onopen = () => {
		peer = new Peer({
			initiator: true,
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
					// Optional TURN:
					// { urls: 'turn:your.turn.server', username: 'user', credential: 'pass' }
				],
			},
		});

		qrString.value = `${location.origin}/login?sessionId=${encodeURIComponent(sessionId)}`;

		peer.on('signal', (signal) => {
			console.log('📡 Sending offer to signaling server');
			socket.send(JSON.stringify({ sessionId, role: 'host', signal }));
		});

		peer.on('connect', () => {
			console.log('✅ Host connected to guest');
		});

		peer.on('data', (data) => {
			console.log('📩 Host received:', data.toString());
			const msg = JSON.parse(data);
			if (msg.type === 'auth-request') {
				authCode.value = msg.authCode;
				console.log('🪪 Received auth code from guest:', msg.authCode);
			}
			if (msg.success) {
				$swal.fire({
					icon: 'success',
					title: 'Device connected',
					timer: 5000,
				});
				$mitt.emit('modal::close');
			}
		});

		socket.onmessage = (event) => {
			const msg = JSON.parse(event.data);
			if (msg.signal) {
				console.log('📡 Host received answer');
				peer.signal(msg.signal); // apply guest answer
			}
		};
	};

	socket.onerror = (e) => console.error('WebSocket error:', e);
};

const approveGuest = () => {
	if (!peer || !authCode.value) return;

	const encryptedKey = $enigma.encryptDataSync($user.account.privateKey, authCode.value);

	peer.send(
		JSON.stringify({
			encryptedKey,
			name: $user.accountInfo.name,
			notes: $user.accountInfo.notes,
			avatar: $user.accountInfo.avatar,
		}),
	);
	authCode.value = null;
};
</script>
