<template>
	<Account_Item :self="true" class="mb-2" />

	<div class="border-bottom pt-1 mx-2 mb-2"></div>

	<router-link :to="{ name: 'account_info' }" custom v-slot="{ isExactActive, navigate }">
		<div class="_sub_menu_btn" :class="{ _active: isExactActive }" @click="select(navigate)">
			<div class="_i_block">
				<i class="_icon_profile" :class="{ _active: isExactActive }"></i>
			</div>
			<div>Identity</div>
		</div>
	</router-link>

	<router-link :to="{ name: 'account_backups' }" custom v-slot="{ isExactActive, navigate }">
		<div class="_sub_menu_btn" :class="{ _active: isExactActive }" @click="select(navigate)">
			<div class="_i_block">
				<i class="_icon_backups" :class="{ _active: isExactActive }"></i>
			</div>
			<div>Backups</div>
		</div>
	</router-link>

	<router-link :to="{ name: 'account_shares' }" custom v-slot="{ isExactActive, navigate }">
		<div class="_sub_menu_btn" :class="{ _active: isExactActive }" @click="select(navigate)">
			<div class="_i_block">
				<i class="_icon_shares" :class="{ _active: isExactActive }"></i>
			</div>
			<div>Shares</div>
		</div>
	</router-link>

	<router-link :to="{ name: 'backup_restore' }" custom v-slot="{ isExactActive, navigate }">
		<div class="_sub_menu_btn" :class="{ _active: isExactActive }" @click="select(navigate)">
			<div class="_i_block">
				<i class="_icon_restore" :class="{ _active: isExactActive }"></i>
			</div>
			<div>Restore shares</div>
		</div>
	</router-link>

	<router-link :to="{ name: 'account_notifications' }" custom v-slot="{ isExactActive, navigate }">
		<div class="_sub_menu_btn" :class="{ _active: isExactActive }" @click="select(navigate)">
			<div class="_i_block">
				<i class="_icon_notifications" :class="{ _active: isExactActive }"></i>
			</div>
			<div>Notifications</div>
		</div>
	</router-link>

	<router-link :to="{ name: 'account_transactions' }" custom v-slot="{ isExactActive, navigate }">
		<div class="_sub_menu_btn" :class="{ _active: isExactActive }" @click="select(navigate)">
			<div class="_i_block">
				<i class="_icon_transactions" :class="{ _active: isExactActive }"></i>
			</div>
			<div>Transactions</div>
		</div>
	</router-link>
	<!--router-link :to="{ name: 'account_admin' }" custom v-slot="{ isExactActive, navigate }">
		<div class="_sub_menu_btn" :class="{ _active: isExactActive }" @click="select(navigate)">
			<div class="_i_block">
				<i class="_icon_admin" :class="{ _active: isExactActive }"></i>
			</div>
			<div>Administration</div>
		</div>
	</router-link-->
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
@import '@/scss/breakpoints.scss';
._account {
	._avatar {
		height: 3.2rem;
		width: 3.2rem;
		margin-right: 0.6rem;
		margin-left: 0.2rem;
	}
}
</style>

<script setup>
import Account_Item from '@/components/Account_Item.vue';
import { inject } from 'vue';

const $menuOpened = inject('$menuOpened');

const select = (navigate) => {
	$menuOpened.value = false;
	navigate();
};
</script>
