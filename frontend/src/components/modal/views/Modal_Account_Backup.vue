<template>
	<!-- Header -->
	<div class="p-2">
		<Account_Backup @backup="$mitt.emit('modal::close')" :show-local="inputData.showLocal" />
	</div>
</template>

<script setup>
import { inject } from 'vue';
import Account_Backup from '@/components/Account_Backup.vue';
const $mitt = inject('$mitt');
const { inputData } = defineProps({ inputData: { type: Object } });
</script>
