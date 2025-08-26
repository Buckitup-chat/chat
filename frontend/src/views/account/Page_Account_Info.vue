<template>
	<FullContentBlock v-if="accountIn">
		<template #header><div class="fw-bold fs-5 py-1">Account info</div> </template>
		<template #content>
			<div class="_full_width_block">
				<Account_Info :account-in="accountIn" :self="true" ref="accountInfo" @update="updateAccount" />

				<div class="d-flex justify-content-center align-items-center mt-4 mb-3">
					<button type="button" class="btn btn-dark rounded-pill _action_btn" @click="$mitt.emit('modal::open', { id: 'account_dxos_invite' })">
						<i class="_icon_reload bg-white"></i>
					</button>

					<button type="button" class="btn btn-dark rounded-pill _action_btn" @click="$mitt.emit('modal::open', { id: 'add_contact_handshake' })" v-tooltip="'Share with contact'">
						<i class="_icon_share bg-white"></i>
					</button>

					<button type="button" class="btn btn-dark rounded-pill _action_btn" @click="$mitt.emit('modal::open', { id: 'account_backup' })">
						<i class="_icon_backups bg-white"></i>
					</button>

					<button type="button" class="btn btn-dark rounded-pill _action_btn" @click="deleteAccount()">
						<i class="_icon_delete bg-white"></i>
					</button>
				</div>
			</div>
		</template>
	</FullContentBlock>
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
@import '@/scss/breakpoints.scss';

._full_width_block {
	max-width: 30rem;
	width: 100%;
}
._action_btn {
	padding: 0.8rem;
	@include media-breakpoint-up(sm) {
		padding: 1.2rem;
	}
	margin-left: 0.3rem;
	margin-right: 0.3rem;
	i {
		height: 1.5rem;
		width: 1.5rem;
	}
}
</style>

<script setup>
import { inject, computed } from 'vue';
import Account_Info from '@/components/Account_Info.vue';
import FullContentBlock from '@/components/FullContentBlock.vue';

const $user = inject('$user');
const $swalModal = inject('$swalModal');
const $router = inject('$router');
const $mitt = inject('$mitt');

const accountIn = computed(() => {
	return {
		...JSON.parse(JSON.stringify($user.account)),
		...JSON.parse(JSON.stringify($user.accountInfo)),
	};
});

async function updateAccount(acc) {
	$user.accountInfo.name = acc.name;
	$user.accountInfo.avatar = acc.avatar;
	$user.accountInfo.notes = acc.notes;
}

const deleteAccount = async () => {
	if (!(await $swalModal.value.open({ id: 'delete_account' }))) return;
	const idx = $user.vaults.findIndex((v) => v.address === $user.account.address);
	if (idx > -1) $user.vaults.splice(idx, 1);

	$user.logout();
	$router.push({ name: 'login' });
};
</script>
