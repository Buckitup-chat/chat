<template>
	<FullContentBlock v-if="$user.account">
		<template #header><div class="fw-bold fs-5 py-1">Restore from shares</div> </template>
		<template #content>
			<div class="_full_width_block">
				<RestoreFromShares @restore="setSecret" @account="setAccount" :key="updateKey" />
			</div>
		</template>
	</FullContentBlock>
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
._full_width_block {
	max-width: 50rem;
	width: 100%;
}
</style>

<script setup>
import { ref, onMounted, watch, inject, computed } from 'vue';
import FullContentBlock from '@/components/FullContentBlock.vue';
import RestoreFromShares from '@/views/backup/RestoreFromShares.vue';

const secretText = ref(); // 'uehfuh ewufhwue huwehufuhuehu ehfuehuewhu uewhfuewh uhuwef uefhuwehwfhhhhhhhhhhhhhhhhhh wehfuwehfuwhefuhweufhuehuwifhwuieh wuehfuwefhuwhfuiw'
const $web3 = inject('$web3');
const $user = inject('$user');
const $swal = inject('$swal');
const $router = inject('$router');
const $route = inject('$route');
const updateKey = ref(0);

const setSecret = async (s) => {
	secretText.value = s;
};

onMounted(() => {
	//console.log($route.state);
});

const setAccount = async (s) => {
	updateKey.value++;
	secretText.value = null;
	$swal.fire({
		icon: 'success',
		title: 'Account restored',
		timer: 5000,
	});
	$router.push({ name: 'account_info' });
};
</script>
