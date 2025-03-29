<template>
	<!-- Header -->

	<div class="mb-1 mt-2 text-center fs-5">Account will be completely wiped from this device</div>
	<div class="mb-3 text-center text-danger">Make sure you made backup before continue</div>

	<div class="d-flex align-items-center justify-content-center">
		<div class="form-check form-switch mb-2">
			<input class="form-check-input" type="checkbox" role="switch" id="setpassword" v-model="confirmed" />
			<label class="form-check-label d-flex align-items-center _pointer small text-center" for="setpassword"> I understand that it will erase all data </label>
		</div>
	</div>

	<div class="border-bottom opacity-75 my-2"></div>

	<div class="d-flex justify-content-center mt-3">
		<button type="button" class="btn btn-outline-dark" @click="cancel()">
			<trn k="tx_confirm.cancel"> Cancel </trn>
		</button>
		<button type="button" class="btn btn-dark ms-2" @click="backup()" v-if="$user.account">
			<trn k="tx_confirm.cancel"> Backup </trn>
		</button>
		<button type="button" class="btn btn-danger ms-2 px-4" @click="confirm()" :disabled="!confirmed">
			<trn k="tx_confirm.ok"> Delete </trn>
		</button>
	</div>
</template>

<script setup>
import { inject, ref } from 'vue';

const $mitt = inject('$mitt');
const confirmed = ref();

const { data } = defineProps({
	data: { type: Object, required: true },
});

function cancel() {
	$mitt.emit('swal::close', false);
}

function backup() {
	$mitt.emit('swal::close', false);
	$mitt.emit('modal::open', { id: 'account_backup', showLocal: true });
}

function confirm() {
	$mitt.emit('swal::close', 'ok');
}
</script>
