<template>
	<!-- Header -->
	<template v-if="!scanning">
		<div class="d-flex align-items-center justify-content-between mb-2">
			<div class="d-flex align-items-center">
				<div class="_modal_icon _icon_profile bg-black me-2"></div>
				<div>
					<div class="fs-5">Add contact</div>
				</div>
			</div>
			<div class="d-flex">
				<div class="btn _icon_times bg-dark" @click="closeModal()"></div>
			</div>
		</div>
	</template>

	<div class="_main">
		<template v-if="!scanning && !contact && !publicKey && !countdown">
			<!--div class="_divider my-3">Your account</div-->

			<div class="px-3 d-flex justify-content-center">
				<Account_Item :self="true" />
			</div>
		</template>

		<template v-if="!scanning && !contact && !publicKey && !manual && !countdown">
			<div class="_divider my-3">Scan QR code of trusted contact</div>

			<div class="d-flex _input_block py-4 mb-3">
				<img src="/img/handshake_tutorial.svg" alt="" class="w-100" />
			</div>

			<div class="text-center text-secondary mb-1 small">
				Hold the phones facing each other. Align cameras with QR codes at 10-20 cm, adjust if needed. Once successful, the qr turns green, the phone vibrates and new contact will appear for
				adding. The exact positioning may vary depending on your phone's specifications.
			</div>
		</template>

		<!-- Display QR Code for Current State -->
		<div class="text-center text-secondary fw-bold mb-1 fs-4" v-if="countdown">Turn phones to each other</div>
		<div class="text-center fw-bold fs-1" v-if="countdown">
			{{ countdown }}
		</div>

		<div class="_qrh">
			<div class="_qrh_wrapper" :class="{ _hidden: !showQr }">
				<div class="_qrh_container">
					<canvas ref="qrCode"></canvas>
				</div>
			</div>
			<div class="_qrh_scanner" :class="{ _hidden: !showCamera }">
				<video ref="qrScannerEl"></video>
			</div>
		</div>

		<div class="row justify-content-center gx-2 mt-3 mb-2" v-if="!contact && !countdown">
			<div class="col-30">
				<button type="button" class="btn btn-dark btn-lg w-100" @click="toggleScanner()">
					<span v-if="!scanning">Start handshake scanning</span>
					<span v-if="scanning">Scanning... Click to stop</span>
				</button>
			</div>
		</div>

		<div class="row justify-content-center gx-2 mt-3 mb-2" v-if="contact">
			<div class="col-30">
				<button type="button" class="btn btn-outline-dark w-100" @click="toggleScanner()">
					{{ publicKey ? 'Start handshake scanning' : 'Scan again' }}
				</button>
			</div>
		</div>

		<div class="row justify-content-center gx-2 mt-3 mb-2" v-if="!scanning && !manual && !countdown">
			<div class="col-30">
				<button type="button" class="btn btn-outline-dark w-100" @click="setManually()">Add manually</button>
			</div>
		</div>

		<template v-if="manual">
			<div class="_warning mb-2">
				<i class="_icon_warning bg-warning mb-2"></i>
				<div class="fw-bold mb-2">Verify Before Connecting</div>
				<div class="text-secondary">Sharing public keys over unsecured channels may expose you to risks. Always verify the key’s authenticity before adding a contact.</div>
			</div>

			<div class="d-flex mb-2">
				<input class="form-control" placeholder="Public key of trusted contact" type="text" v-model="publicKey" />
				<button class="btn btn-dark ms-2" v-if="publicKey" @click="addManually()">Add</button>
			</div>
		</template>

		<div class="row justify-content-center gx-2 mb-2 mt-3" v-if="contact">
			<div class="_divider mb-3">
				{{ isInContacts ? 'Existing contact' : 'Contact found' }}
			</div>
			<div class="fs-4 mb-4 text-center">
				<span class="fw-bold">{{ contact.name ? contact.name : 'Unnamed' }}</span>
				<span class="text-secondary ms-2">[{{ contact.publicKey.slice(-5) }}]</span>
			</div>

			<div class="col-30">
				<button type="button" class="btn btn-dark btn-lg w-100" @click="addContact()">
					{{ isInContacts ? 'Open contact' : 'Save contact' }}
				</button>
			</div>
		</div>
	</div>
</template>

<style lang="scss">
@import '@/scss/variables.scss';
._warning {
	border-radius: $blockRadiusSm;
	padding: 1rem;
	background-color: rgba($warning, 0.2);
	text-align: center;

	._icon_warning {
		height: 2rem;
	}
}

._qrh {
	overflow: hidden;
	position: relative;

	._qrh_scanner {
		width: 100%;
		z-index: 2;
		border-radius: 1rem;
		overflow: hidden;
		pointer-events: none;
		max-height: 400px;

		&._hidden {
			position: absolute;
			top: -9999px;
			height: 1px;
			max-height: unset;
			opacity: 0 !important;
		}

		video {
			width: 100%;
		}
	}

	._qrh_wrapper {
		justify-content: center;
		z-index: 1;
		display: flex;

		&._hidden {
			height: 0px;
			display: none;
		}
		._qrh_container {
			width: 100% !important;
			max-width: 470px !important;
			canvas {
				width: 100% !important;
				height: auto !important;
			}
		}
	}
}
</style>

<script setup>
import { ref, inject, onMounted, onBeforeUnmount, computed } from 'vue';
import QrScanner from 'qr-scanner';
import QRCode from 'qrcode';
import Account_Item from '@/components/Account_Item.vue';
import { utils } from 'ethers';
import { Expando, create } from '@dxos/client/echo';
import dayjs from 'dayjs';

const $user = inject('$user');
const $mitt = inject('$mitt');
const $router = inject('$router');
const $swal = inject('$swal');
const $enigma = inject('$enigma');
const $loader = inject('$loader');
const $menuOpened = inject('$menuOpened');
const hasCamera = ref();
const contact = ref(null);
const qrCode = ref(null);
const qrScanner = ref(null);
const qrScannerEl = ref(null);
const manual = ref();
const scanning = ref();
const showQr = ref();
const showCamera = ref();

const countdown = ref();

const options = {
	staticString: 'BKP',
	scanningColor: '#000',
	detectedColor: '#8e2b77',
	verifiedColor: '#611e52',
};
const state = ref({
	challenge: null,
	signature: null,
	verified: 0,
	completed: false,
	contactChallenge: null,
	contactAddress: null,
	contactPublicKey: null,
	contactName: null,
	contactVerified: 0,
});

const { inputData } = defineProps({ inputData: { type: Object } });
//console.log('inputData', inputData);

onMounted(async () => {
	try {
		// Get all media devices
		const devices = await navigator.mediaDevices.enumerateDevices();
		// Check if there is at least one video input (camera)
		hasCamera.value = devices.some((device) => device.kind === 'videoinput');
	} catch (error) {
		console.error('Error checking camera availability:', error);
	}

	if (hasCamera.value) {
		qrScanner.value = new QrScanner(qrScannerEl.value, (result) => readQr(result.data), {
			returnDetailedScanResult: true,
			preferredCamera: 'user',
			highlightScanRegion: true,
			highlightCodeOutline: true,
			calculateScanRegion: (video) => {
				const width = video.videoWidth;
				const height = video.videoHeight;
				const scanSize = 0.95; // 100% of video size
				return {
					x: (width * (1 - scanSize)) / 2, // Center horizontally
					y: (height * (1 - scanSize)) / 2, // Center vertically
					width: width * scanSize, // 80% width
					height: height * scanSize, // 80% height
				};
			},
		});

		if (inputData.startScan) toggleScanner();
	}
});

onBeforeUnmount(() => {
	if (countdownInterval) clearInterval(countdownInterval);
	if (stopScanTimeout) clearTimeout(countdownInterval);
	try {
		qrScanner.value.dispose();
	} catch (error) {}
});

let countdownInterval = null;
async function toggleScanner() {
	manual.value = false;
	contact.value = null;
	publicKey.value = null;
	try {
		if (scanning.value && qrScanner.value) {
			await stopScan();
			updateQr();
			return;
		}
		reset();
		$loader.show();

		await wait(100);

		await qrScanner.value.start();
		$loader.hide();
		showCamera.value = true;

		// Start countdown interval
		countdown.value = 2;
		countdownInterval = setInterval(() => {
			countdown.value -= 1;
			if (countdown.value <= 0) {
				clearInterval(countdownInterval);
				showCamera.value = false;
				scanning.value = true;

				generateChallenge();
				showQr.value = true;
				updateQr();
			}
		}, 1000);
	} catch (error) {
		console.error('Init Scanning error:', error);
		$loader.hide();
	}
}

let stopScanTimeout = null;
function startAutoStopCountdown(delay = 1000) {
	if (stopScanTimeout) clearTimeout(stopScanTimeout);
	stopScanTimeout = setTimeout(() => stopScan(), delay);
}

const readQr = (msg) => {
	try {
		// Extract the fixed parts based on known lengths
		const verified = parseInt(msg[0]); // First character (1 char)
		const challenge = msg.slice(1, 19); // Next 18 characters (2nd to 19th char)
		const signature = msg.length > 19 ? msg.slice(19, 107) : null; // 19th to 107th char (if present)
		const displayNameEnc = msg.length > 107 ? msg.slice(107) : null;
		if (challenge) {
			const decodedChallengeBytes = utils.base58.decode(challenge);
			const contactChallengeDec = new TextDecoder().decode(decodedChallengeBytes);
			if (challenge && contactChallengeDec.startsWith(options.staticString)) {
				if (stopScanTimeout) startAutoStopCountdown();

				if (state.value.contactChallenge !== challenge) {
					if (state.value.contactChallenge) {
						reset();
					}
					state.value.contactChallenge = challenge;
				}
				if (signature) {
					const decodedNameBytes = utils.base58.decode(displayNameEnc);
					const displayName = new TextDecoder().decode(decodedNameBytes);
					const publicKeyCompact = $enigma.recoverPublicKey(state.value.challenge + displayName, signature);
					const publicKey = '0x' + $enigma.convertPublicKeyToHex(publicKeyCompact);
					state.value.contactAddress = utils.computeAddress(publicKey);
					state.value.contactPublicKey = publicKey;
					state.value.contactName = displayName;
					state.value.verified = 1;
					state.value.contactVerified = verified;
				}
				updateQr();
			}
		}
	} catch (error) {
		console.error('Init Scanning error:', error);
	}
};

const updateQr = async () => {
	if (qrCode.value && state.value.challenge) {
		let color = options.scanningColor;
		if (state.value.contactChallenge && !state.value.signature) {
			state.value.signature = $enigma.signChallenge(state.value.contactChallenge + $user.accountInfo.name, $user.account.privateKeyB64);
			if ('vibrate' in navigator) navigator.vibrate([50]);
		}

		const displayName = state.value.signature ? utils.base58.encode(new TextEncoder().encode($user.accountInfo.name)) : '';
		const msg = `${state.value.verified}${state.value.challenge}${state.value.signature || ''}${displayName}`;

		if (state.value.signature) color = options.detectedColor;
		if (state.value.verified && state.value.contactVerified) color = options.verifiedColor;

		QRCode.toCanvas(qrCode.value, msg, {
			errorCorrectionLevel: 'M',
			height: 360,
			width: 360,
			quality: 1,
			margin: 0,
			color: { dark: color },
		});

		if (state.value.verified && state.value.contactVerified && !state.value.completed) {
			state.value.completed = true;

			contact.value = {
				address: state.value.contactAddress,
				publicKey: state.value.contactPublicKey,
				name: state.value.contactName,
			};

			if ('vibrate' in navigator) navigator.vibrate([500, 100, 500, 100, 500]);

			startAutoStopCountdown();
		}
	}
};

const generateChallenge = () => {
	const staticBytes = utils.toUtf8Bytes(options.staticString); // Convert 'buckitup' to bytes
	const randomBytes = utils.randomBytes(10); // Generate 16 random bytes
	state.value.challenge = utils.base58.encode(Buffer.concat([staticBytes, randomBytes])); // .toString('base58')
};

const isInContacts = computed(() => {
	return $user.contacts.find((e) => e.address.toLowerCase() === contact.value.address.toLowerCase());
});

function closeModal() {
	$mitt.emit('modal::close');
}

const addContact = async () => {
	try {
		if ($user.account.address === contact.value.address) {
			$swal.fire({
				icon: 'warning',
				title: 'It`s your own account',
				timer: 15000,
			});
			return;
		}

		if (isInContacts.value) {
			$swal.fire({
				icon: 'success',
				title: 'Contact already in your list',
				timer: 15000,
			});
			contact.value = isInContacts.value;
			manual.value = false;
			//$router.push({ name: 'contact', params: { address: contact.address } });
			return;
		}

		$user.contacts.push(contact.value);

		const contactDx = create(Expando, {
			...$enigma.encryptObjectKeys(contact.value, $user.contactKeys, $user.account.privateKey),
			updatedAt: dayjs().valueOf(),
			type: 'contact',
		});

		await $user.space.db.add(contactDx);
		//$user.contactsDx.value.push(contactDx);

		$swal.fire({
			icon: 'success',
			title: 'Contact added',
			footer: 'Now you can name it and make notes',
			timer: 15000,
		});
		$menuOpened.value = false;
		$router.push({ name: 'contact', params: { address: contact.value.address } });
		closeModal();
	} catch (error) {}
};

const setManually = async () => {
	stopScan();
	contact.value = null;
	manual.value = true;
	scanning.value = false;
	publicKey.value = null;
};

const publicKey = ref();
const addManually = async () => {
	let address;
	try {
		address = utils.computeAddress(publicKey.value.trim());
	} catch (error) {}
	if (!address) {
		$swal.fire({
			icon: 'warning',
			title: 'Invalid public key',
			timer: 15000,
		});
		publicKey.value = null;
		return;
	}

	contact.value = {
		publicKey: publicKey.value.trim(),
		address,
	};
	manual.value = false;
	addContact();
};

const reset = () => {
	state.value.verified = 0;
	state.value.completed = 0;
	state.value.signature = null;
	state.value.contactChallenge = null;
	state.value.contactAddress = null;
	state.value.contactPublicKey = null;
	state.value.contactName = null;
	state.value.contactVerified = 0;
};

const stopScan = async () => {
	scanning.value = false;
	showQr.value = false;
	if (qrScanner.value) {
		try {
			await qrScanner.value.stop();
		} catch (error) {}
	}
};

const wait = (delay = 500) => {
	return new Promise((resolve) =>
		setTimeout(() => {
			resolve();
		}, delay),
	);
};
</script>
