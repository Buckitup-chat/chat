<template>
	<!-- Header -->

	<div class="mb-1 mt-2 text-center fs-5">Contact will be hidden from list</div>

	<div class="border-bottom opacity-75 my-2"></div>

	<div class="d-flex justify-content-center mt-3">
		<button type="button" class="btn btn-outline-dark" @click="cancel()">
			<trn k="tx_confirm.cancel"> Cancel </trn>
		</button>
		<button type="button" class="btn btn-danger ms-2 px-4" @click="confirm()">
			<trn k="tx_confirm.ok"> Hide </trn>
		</button>
	</div>
</template>

<script setup>
import { inject, ref } from 'vue';

const $mitt = inject('$mitt');

function cancel() {
	$mitt.emit('swal::close', false);
}

function confirm() {
	$mitt.emit('swal::close', 'ok');
}
</script>
