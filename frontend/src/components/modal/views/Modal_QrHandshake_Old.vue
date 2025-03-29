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
			<div class="_divider my-3">Your account</div>

			<div class="px-3 d-flex justify-content-center">
				<Account_Item :self="true" />
			</div>
		</template>

		<template v-if="!scanning && !contact && !publicKey && !manual && !countdown">
			<div class="_divider my-3">Scan QR code of trusted contact</div>

			<div class="d-flex _input_block py-4 mb-3">
				<img src="/img/handshake_tutorial.svg" alt="" class="w-100" />
			</div>

			<div class="text-center text-secondary mb-3">
				Hold the phones facing each other. <br />
				Align cameras with QR codes at 10-20 cm, adjust if needed. <br />
				Once successful, the qr turns green, the phone vibrates and new contact will appear for adding. <br />
				The exact positioning may vary depending on your phone's specifications. <br />
			</div>
		</template>

		<!-- Display QR Code for Current State -->
		<div ref="qrHandshakeEl" class="mt-2"></div>

		<div class="_qrh">
			<div class="_qrh_wrapper" id="qrCodeWrapper">
				<div class="_qrh_container">
					<canvas id="qrCode"></canvas>
				</div>
			</div>
			<div class="_qrh_scanner" id="qrScannerWrap">
				<video id="qrScanner"></video>
			</div>
		</div>

		<div class="text-center fw-bold fs-1" v-if="countdown">
			{{ countdown }}
		</div>

		<div class="row justify-content-center gx-2 mt-3 mb-2" v-if="!contact && !countdown">
			<div class="col-30">
				<button type="button" class="btn btn-dark btn-lg w-100" @click="toggleScanner()">
					<span v-if="!scanning">Start handshake scanning</span>
					<span v-if="scanning">Scanning... Click to stop</span>
				</button>
			</div>
		</div>

		<div class="row justify-content-center gx-2 mb-2" v-if="contact">
			<div class="_divider mb-3">
				{{ isInContacts ? 'Existing contact' : 'Contact found' }}
			</div>
			<div class="fs-4 mb-4 text-center">
				<span class="fw-bold">{{ contact.name ? contact.name : 'Unnamed' }}</span>
				<span class="text-secondary ms-2">[{{ contact.publicKey.slice(-5) }}]</span>
			</div>

			<div class="col-30">
				<button type="button" class="btn btn-dark btn-lg w-100" @click="addContact()">
					{{ isInContacts ? 'Open contact' : 'Add contact' }}
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
		//
		//opacity: 0 !important;
		border-radius: 1rem;
		overflow: hidden;
		pointer-events: none;

		&._hidden {
			position: absolute;
			top: -9999px;
			height: 1px;
		}

		video {
			width: 100%;
		}
	}

	._qrh_wrapper {
		justify-content: center;
		z-index: 1;
		height: 0px;

		._qrh_container {
			width: 100% !important;
			max-width: 450px !important;

			&._qrh_detected {
				background-color: #e99f00;
			}

			&._qrh_verified {
				background-color: #07ce00;
			}

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
import QRHandshakeManager from '@/libs/QRHandshakeManager';
import Account_Item from '@/components/Account_Item.vue';
import { utils } from 'ethers';
import { Expando, create } from '@dxos/client/echo';
import dayjs from 'dayjs';

const $user = inject('$user');
const $mitt = inject('$mitt');
const $router = inject('$router');
const $swal = inject('$swal');
const $enigma = inject('$enigma');

const hasCamera = ref();
const contact = ref(null);
const qrHandshakeEl = ref(null);
const qrHandshakeInstance = ref(null);
const manual = ref();
const scanning = ref();
const countdown = ref();

const { inputData } = defineProps({ inputData: { type: Object } });
console.log('inputData', inputData);

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
		qrHandshakeInstance.value = new QRHandshakeManager(
			qrHandshakeEl.value,
			{
				name: $user.accountInfo.name,
				privateKeyB64: $user.account.privateKeyB64,
			},
			{
				scanningColor: '#000',
				detectedColor: '#8e2b77',
				verifiedColor: '#611e52',
			},
		);
		qrHandshakeInstance.value.addEventListener('handshakeCompleted', (event) => {
			console.log('Handshake completed:', event.detail);
			contact.value = event.detail;
			scanning.value = false;
		});
		qrHandshakeInstance.value.addEventListener('scanning', (event) => {
			console.log('Handshake scanning:', event.detail);
			scanning.value = event.detail;
		});
		qrHandshakeInstance.value.addEventListener('handshakeCountdown', (event) => {
			console.log('Handshake countdown:', event.detail);
			countdown.value = event.detail;
		});

		if (inputData.startScan) {
			toggleScanner();
		}
	}
});

onBeforeUnmount(() => {
	try {
		qrHandshakeInstance.value.dispose();
	} catch (error) {}
});

function toggleScanner() {
	manual.value = false;
	contact.value = null;
	publicKey.value = null;
	qrHandshakeInstance.value.toggleScanner();
}

const isInContacts = computed(() => {
	return $user.contacts.find((e) => e.address.toLowerCase() === contact.value.address.toLowerCase());
});

function closeModal() {
	try {
		qrHandshakeInstance.value.dispose();
	} catch (error) {}

	$mitt.emit('modal::close');
}

const addContact = async () => {
	if (!isInContacts.value) {
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
	}
	$router.push({ name: 'contact', params: { address: contact.value.address } });
	closeModal();
};

const setManually = async () => {
	qrHandshakeInstance.value.stopScan();
	contact.value = null;
	manual.value = true;
	scanning.value = false;
	publicKey.value = null;
};

const publicKey = ref();
const address = computed(() => {
	if (!publicKey.value) return;
	try {
		return utils.computeAddress(publicKey.value.trim());
	} catch (error) {
		return null;
	}
});

const addManually = async () => {
	if (!address.value) {
		$swal.fire({
			icon: 'warning',
			title: 'Invalid public key',
			timer: 15000,
		});
		publicKey.value = null;
		return;
	}

	if ($user.account.address === address.value) {
		$swal.fire({
			icon: 'warning',
			title: 'It`s your own public key',
			timer: 15000,
		});
		//$router.push({ name: 'profile' });
		return;
	}

	const existentContact = $user.contacts.find((e) => e.address === address.value);
	if (existentContact) {
		$swal.fire({
			icon: 'success',
			title: 'Contact already in your list',
			timer: 15000,
		});
		contact.value = existentContact;
		manual.value = false;
		//$router.push({ name: 'contact', params: { address: contact.address } });
		return;
	}

	contact.value = {
		publicKey: publicKey.value.trim(),
		address: address.value,
	};
	manual.value = false;
	addContact();
	//publicKey.value = null;
	return;
	$mitt.emit('modal::close');
	$user.contacts.push({});
	$user.updateVault();
	$router.push({ name: 'contact', params: { address: contact.address } });
};
</script>
