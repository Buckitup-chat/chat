<template>
	<div>Room</div>
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
</style>

<script setup>
import { ref, onMounted, watch, inject, computed } from 'vue';
import { useRoute } from 'vue-router';

const $user = inject('$user');
const $web3 = inject('$web3');
const $swal = inject('$swal');
const $route = useRoute();
const $loader = inject('$loader');

const contact = computed(() => {
	return $user.contacts.find((e) => e.address === $route.params.address);
});
</script>
