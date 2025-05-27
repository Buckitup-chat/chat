<template>
	<Contacts_List @select="select" :selected="selected" v-if="$user.chats?.length" />

	<div class="fs-5 text-center" v-if="!$user.chats?.length">
		<p>Your list is empty</p>
	</div>
</template>

<script setup>
import Contacts_List from '@/views/contacts/Contacts_List.vue';
import { ref, inject } from 'vue';

const $router = inject('$router');
const $user = inject('$user');
const selected = ref([]);

const select = (address) => {
	selected.value = [address];
	$router.push({ name: 'chat', params: { address } });
};
</script>
