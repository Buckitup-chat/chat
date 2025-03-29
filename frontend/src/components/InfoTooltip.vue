<template>
	<VDropdown placement="top" :distance="8" theme="tooltip" :autoHideOnMousedown="false" :triggers="['hover', 'click']">
		<i class="_icon_info _pointer"></i>
		<template #popper>
			<div class="p-2 _content">
				<div class="">{{ title }}</div>
				<div class="small" v-html="content"></div>
			</div>
		</template>
	</VDropdown>
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
._icon_info {
	background-color: $grey_dark;
}
._content {
	max-width: 15rem;
}
</style>

<script setup>
const { title, content, html } = defineProps({
	title: { type: String, required: true },
	content: { type: String, required: true },
});
</script>
