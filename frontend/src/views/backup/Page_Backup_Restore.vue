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
import { ref, inject } from 'vue';
import FullContentBlock from '@/components/FullContentBlock.vue';
import RestoreFromShares from '@/views/backup/RestoreFromShares.vue';

const secretText = ref();
const $user = inject('$user');
const $swal = inject('$swal');
const $router = inject('$router');
const updateKey = ref(0);

const setSecret = async (s) => {
	secretText.value = s;
};

const setAccount = async () => {
	updateKey.value++;
	secretText.value = null;
	$swal.fire({
		icon: 'success',
		title: 'Account restored',
		timer: 5000,
	});
	$router.replace({ name: 'account_info' });
};
</script>
