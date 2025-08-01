<template>
	<FullContentBlock v-if="$user.account">
		<template #header><div class="fw-bold fs-5 py-1">Administration</div> </template>
		<template #content>
			<div class="_full_width_block">Administration</div>
		</template>
	</FullContentBlock>
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
._full_width_block {
	max-width: 30rem;
	width: 100%;
}
</style>

<script setup>
import FullContentBlock from '@/components/FullContentBlock.vue';
</script>
