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

	<div class="d-flex justify-content-center align-items-center flex-column mt-2 mb-3" v-if="authCode && mode === 'manual'">
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
import { ref, onMounted, watch, inject, computed, onUnmounted } from 'vue';
import { InvitationEncoder } from '@dxos/client/invitations';
import copyToClipboard from '@/utils/copyToClipboard';
import QRCode from 'qrcode';
import { SpaceMember } from '@dxos/protocols/proto/dxos/halo/credentials';
import { Expando, create } from '@dxos/client/echo';
import dayjs from 'dayjs';

const qrCode = ref(); // 'uehfuh ewufhwue huwehufuhuehu ehfuehuewhu uewhfuewh uhuwef uefhuwehwfhhhhhhhhhhhhhhhhhh wehfuwehfuwhefuhweufhuehuwifhwuieh wuehfuwefhuwhfuiw'
const $router = inject('$router');
const $swal = inject('$swal');
const $mitt = inject('$mitt');
const $user = inject('$user');
const $enigma = inject('$enigma');

const intervalId = ref(null);
const invitation = ref();
const invitationCode = ref();
const authCode = ref();
const encryptionKey = ref();
const qrString = ref();
const showAuthCode = ref();

const mode = ref();

const newMemberJoined = ref(false);
const currentMembers = ref([]);
let unsubscibeMembers, unsubscibeInvitation, unsubscibeEncryptedAccount;
let joined;

onMounted(async () => {
	await getInvite();
	checkMembers();

	const encryptedAccountQuery = $user.space.db.query((doc) => doc.type === 'encryptedAccount');
	unsubscibeEncryptedAccount = encryptedAccountQuery.subscribe(async ({ objects }) => {
		try {
			let isComplete;
			objects.forEach((o) => {
				if (o.status === 'COMPLETED') isComplete = true;
			});

			if (isComplete) {
				$mitt.emit('modal::close');
				$swal.fire({
					icon: 'success',
					title: 'Device connected',
					timer: 5000,
				});
			}
		} catch (error) {
			console.error('encryptedAccountQuery.subscribe', error);
		}
	});
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

const copyInvite = async () => {
	copyToClipboard(`${location.origin}/login?invitationCode=${invitationCode.value}&encryptionKey=${encryptionKey.value}`);
	mode.value = 'manual';
};

const getInvite = async () => {
	qrString.value = null;
	mode.value = null;
	if (unsubscibeInvitation) {
		try {
			console.log('getInvite unsubscibeInvitation', unsubscibeInvitation);
			unsubscibeInvitation._cleanup();
		} catch (error) {
			console.error('unsubscibeInvitation error', error);
		}
	}

	await removeAllEncryptedAccounts();

	invitation.value = $user.space.share({ persistent: false, role: SpaceMember.Role.ADMIN }); //
	invitationCode.value = InvitationEncoder.encode(invitation.value.get());

	await new Promise((resolve) => setTimeout(resolve, 1000));

	authCode.value = invitation.value.get().authCode;

	encryptionKey.value = $enigma.generateSecurePassword(64);
	qrString.value = `${location.origin}/login?invitationCode=${invitationCode.value}&encryptionKey=${encryptionKey.value}&authCode=${authCode.value}`;

	await removeAllEncryptedAccounts();
	const auth = create(Expando, {
		privateKey: $enigma.encryptDataSync($user.account.privateKey, encryptionKey.value),
		status: 'AWAITING',
		updatedAt: dayjs().valueOf(),
		type: 'encryptedAccount',
	});

	console.log('getInvite auth', auth);
	await $user.space.db.add(auth);

	showAuthCode.value = true;

	//unsubscibeInvitation = invitation.value.subscribe(async (data) => {
	//	console.log('getInvite invitation.value.subscribe', data);
	//	if (data.state >= 2 && !showAuthCode.value) {
	//		showAuthCode.value = true;
	//		await removeAllEncryptedAccounts();
	//		const auth = create(Expando, {
	//			privateKey: $enigma.encryptDataSync($user.account.privateKey, encryptionKey.value),
	//			status: 'AWAITING',
	//			updatedAt: dayjs().valueOf(),
	//			type: 'encryptedAccount',
	//		});
	//		console.log('getInvite auth', auth);
	//		await $user.space.db.add(auth);
	//	}
	//});
};

onUnmounted(() => {
	removeAllEncryptedAccounts();
	if (unsubscibeMembers) {
		try {
			unsubscibeMembers._cleanup();
		} catch (error) {
			console.error('unsubscibeMembers error', error);
		}
	}
	if (unsubscibeEncryptedAccount) {
		try {
			unsubscibeEncryptedAccount();
		} catch (error) {
			console.error('unsubscibeEncryptedAccount error', error);
		}
	}
	if (unsubscibeInvitation) {
		try {
			unsubscibeInvitation._cleanup();
		} catch (error) {
			console.error('unsubscibeInvitation error', error);
		}
	}
});

const checkMembers = () => {
	if (!$user.space) return;
	currentMembers.value = $user.space.members.get();
	unsubscibeMembers = $user.space.members.subscribe(() => {
		const newMembers = $user.space.members.get();
		if (newMembers.length > currentMembers.value.length && !joined) {
			joined = true;
			newMemberJoined.value = true;
			console.log('newMemberJoined', invitation.value);
			console.log('space.members', $user.space.members.get());
		}
		currentMembers.value = newMembers;
	});
};

const removeAllEncryptedAccounts = async () => {
	const encryptedAccountQuery = await $user.space.db.query((doc) => doc.type === 'encryptedAccount').run();
	if (encryptedAccountQuery.objects.length === 0) return;
	for (const encryptedAccount of encryptedAccountQuery.objects) {
		await $user.space.db.remove(encryptedAccount);
	}
	console.log('All encryptedAccount entries removed.');
};
</script>
