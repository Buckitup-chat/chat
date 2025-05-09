<template>
	<!-- Header -->
	<div class="p-2">
		<Account_Info :account-in="account" @update="updateAccount" class="mb-3" v-if="account?.address" />
		<div class="row justify-content-center gx-2 mt-3">
			<div class="col-lg-12 col-xl-10">
				<button type="button" class="btn btn-dark w-100" @click="create()">Create</button>
			</div>
		</div>
	</div>
</template>

<style lang="scss" scoped></style>

<script setup>
import { ref, onMounted, inject } from 'vue';
import Account_Info from '@/components/Account_Info.vue';

const $user = inject('$user');
const $mitt = inject('$mitt');

const $router = inject('$router');
const $encryptionManager = inject('$encryptionManager');

const account = ref();

onMounted(async () => {
	account.value = await $user.generateAccount();
});

const updateAccount = (c) => {
	account.value = c;
};

const create = async () => {
	try {
		await $encryptionManager.createVault({
			keyOptions: {
				username: account.value.name,
				displayName: account.value.name,
			},
			address: account.value.address,
			publicKey: account.value.publicKey,
			avatar: account.value.avatar,
			notes: account.value.notes,
		});

		$user.account = await $user.generateAccount(account.value.privateKey);

		await $encryptionManager.setData($user.toVaultFormat());

		await $user.openStorage({
			name: account.value.name,
			notes: account.value.notes,
			avatar: account.value.avatar,
		});

		$mitt.emit('account::created');
		$mitt.emit('modal::close');
		$router.replace({ name: 'account_info' });
	} catch (error) {
		console.error('create error', error);
	}
};
</script>
