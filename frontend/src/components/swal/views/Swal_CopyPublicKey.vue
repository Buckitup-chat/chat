<template>
	<!-- Header -->

	<div class="_warning">
		<i class="_icon_warning bg-warning mb-2"></i>
		<div class="fw-bold mb-2">Verify before sharing your Public Key</div>
		<div class="text-secondary">Sharing public keys over unsecured channels may expose you to risks. Always verify the recipient authenticity.</div>
	</div>

	<div class="d-flex justify-content-center mt-3">
		<button type="button" class="btn btn-outline-dark" @click="cancel()">
			<trn k="tx_confirm.cancel"> Cancel </trn>
		</button>
		<button type="button" class="btn btn-dark ms-2 px-4" @click="copy()">
			<trn k="tx_confirm.ok"> Copy </trn>
		</button>
	</div>
</template>

<script setup>
import { inject } from 'vue';
import copyToClipboard from '@/utils/copyToClipboard';

const $mitt = inject('$mitt');
const $user = inject('$user');

const { data } = defineProps({
	data: { type: Object, required: true },
});

function cancel() {
	$mitt.emit('swal::close', false);
}

function copy() {
	copyToClipboard($user.account.publicKey);
	$mitt.emit('swal::close', 'ok');
}
</script>

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
</style>
