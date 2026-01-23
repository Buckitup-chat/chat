<template>
	<Chats_List />
</template>

<script setup>
import Chats_List from '@/views/chats/Chats_List.vue';
import { ref, inject } from 'vue';

const $router = inject('$router');
const $user = inject('$user');
const selected = ref([]);

const select = (address) => {
	selected.value = [address];
	$router.push({ name: 'chat', params: { address } });
};
</script>
