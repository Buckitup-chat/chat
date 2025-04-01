<template>
	<div v-if="!$user.registeredMetaWallet">
		<div class="_divider">
			Activate Your Profile
			<InfoTooltip class="align-self-center ms-2" :content="'Register meta address'" />
		</div>
		<div class="text-secondary text-center mb-3">Before creating backups or participating in backups of other users as trusted partie, register your meta address in on-chain public registry</div>

		<div class="row justify-content-center gx-2">
			<div class="col-lg-12 col-xl-10">
				<button type="button" class="btn btn-dark w-100" @click="$mitt.emit('modal::open', { id: 'account_activate' })">Activate</button>
			</div>
		</div>
	</div>
</template>

<script setup>
import { inject } from 'vue';
const $user = inject('$user');
const $mitt = inject('$mitt');
</script>
