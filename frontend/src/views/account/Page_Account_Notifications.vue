<template>
	<FullContentBlock v-if="$user.account">
		<template #header><div class="fw-bold fs-5 py-1">Notifications</div> </template>
		<template #content>
			<div class="_full_width_block">
				<div class="fw-bold text-center">
					Join to <a :href="`https://t.me/${tmBot}`" target="_blank" rel="noopener noreferrer">@{{ tmBot }}</a> and receive instant notifications
				</div>
			</div>
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

const tmBot = TM_BOT;
</script>
