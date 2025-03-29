<template>
	<div>
		<RestoreFromShares @restore="setSecret" @account="setAccount" />
	</div>
</template>

<style lang="scss" scoped></style>

<script setup>
import { ref, onMounted, watch, inject, computed } from 'vue';

import RestoreFromShares from '@/views/backup/RestoreFromShares.vue';

const secretText = ref(); // 'uehfuh ewufhwue huwehufuhuehu ehfuehuewhu uewhfuewh uhuwef uefhuwehwfhhhhhhhhhhhhhhhhhh wehfuwehfuwhefuhweufhuehuwifhwuieh wuehfuwefhuwhfuiw'
const $router = inject('$router');
const $swal = inject('$swal');
const $mitt = inject('$mitt');

const setSecret = (s) => {
	secretText.value = s;
};

const setAccount = async (s) => {
	secretText.value = null;
	$swal.fire({
		icon: 'success',
		title: 'Account restored',
		timer: 5000,
	});
	$mitt.emit('modal::close');
	$router.push({ name: 'account_info' });
};
</script>
