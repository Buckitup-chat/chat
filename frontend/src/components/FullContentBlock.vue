<template>
	<div class="_wrap">
		<div class="_header">
			<div class="_top">
				<div class="d-flex align-items-center w-100">
					<div class="_btn_back" @click="$router.back()" v-if="$router.options.history.state.back && $breakpoint.lt('sm') && !$router.options.history.state.back.includes('login')">
						<i class="_icon_back"></i>
					</div>
					<div class="flex-grow-1">
						<slot name="header"></slot>
					</div>
				</div>

				<!-- toggle -->
				<div class="_toggler" @click="$menuOpened = !$menuOpened" v-if="$breakpoint.lt('md')" ref="toggler">
					<div :class="{ _open: $menuOpened }"><span></span><span></span><span></span><span></span></div>
				</div>
			</div>

			<div class="_bottom">
				<slot name="headerbottom"></slot>
			</div>
		</div>

		<div class="_body">
			<div class="_content">
				<div class="d-flex justify-content-center w-100" :class="blockClass">
					<slot name="content"></slot>
				</div>
			</div>
		</div>
	</div>
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
@import '@/scss/breakpoints.scss';

._wrap {
	display: flex;
	flex-direction: column;
	width: 100%;
	._header {
		padding-top: 0.6rem;
		padding-bottom: 0.6rem;
		padding-left: 1rem;
		padding-right: 0.2rem;
		background-color: $white;
		border-bottom: 1px solid $light_grey2;
		width: 100%;
		._top {
			display: flex;
			align-items: center;
			justify-content: space-between;
			min-height: 2.6rem;
		}
		._bottom {
		}
	}

	._body {
		flex-grow: 1;
		overflow: auto;
		padding: 0.8rem;
		@include media-breakpoint-up(sm) {
			padding: 1rem;
		}

		@include media-breakpoint-up(md) {
			padding: 1rem;
		}
		@include media-breakpoint-up(lg) {
			padding: 1.3rem;
		}
		@include media-breakpoint-up(xl) {
			padding: 1.5rem;
		}

		._content {
			display: flex;
			justify-content: center;
			width: 100%;
		}
	}
}

._toggler {
	border: none;
	padding-right: 1rem;

	div {
		width: 22px;
		height: 20px;
		position: relative;
		transform: rotate(0deg);
		transition: 0.5s ease-in-out;
		cursor: pointer;

		span {
			display: block;
			position: absolute;
			height: 3px;
			width: 100%;
			background: $dark;
			border-radius: 2px;
			opacity: 1;
			left: 0;
			transform: rotate(0deg);
			transition: 0.25s ease-in-out;

			&:nth-child(1) {
				top: 0px;
			}

			&:nth-child(2),
			&:nth-child(3) {
				top: 8px;
			}

			&:nth-child(4) {
				top: 16px;
			}
		}

		&._open {
			span {
				&:nth-child(1) {
					top: 8px;
					width: 0%;
					left: 50%;
				}

				&:nth-child(2) {
					transform: rotate(45deg);
				}

				&:nth-child(3) {
					transform: rotate(-45deg);
				}

				&:nth-child(4) {
					top: 16px;
					width: 0%;
					left: 50%;
				}
			}
		}
	}
}
</style>

<script setup>
import { inject } from 'vue';

const $menuOpened = inject('$menuOpened');
const { blockClass } = defineProps({
	blockClass: { type: String },
});

const $breakpoint = inject('$breakpoint');
</script>
