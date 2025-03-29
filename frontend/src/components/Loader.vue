<template>
	<div tabindex="0" class="vld-overlay is-full-page" :class="{ 'is-active': $loader.enabled }" aria-busy="true" aria-label="Loading" style="z-index: 99999999">
		<div class="vld-background"></div>
		<div class="vld-icon">
			<svg viewBox="0 0 120 30" xmlns="http://www.w3.org/2000/svg" width="100" height="100">
				<circle cx="15" cy="15" r="15">
					<animate attributeName="r" from="15" to="15" begin="0s" dur="0.8s" values="15;9;15" calcMode="linear" repeatCount="indefinite"></animate>
					<animate attributeName="fill-opacity" from="1" to="1" begin="0s" dur="0.8s" values="1;.5;1" calcMode="linear" repeatCount="indefinite"></animate>
				</circle>
				<circle cx="60" cy="15" r="9" fill-opacity="0.3">
					<animate attributeName="r" from="9" to="9" begin="0s" dur="0.8s" values="9;15;9" calcMode="linear" repeatCount="indefinite"></animate>
					<animate attributeName="fill-opacity" from="0.5" to="0.5" begin="0s" dur="0.8s" values=".5;1;.5" calcMode="linear" repeatCount="indefinite"></animate>
				</circle>
				<circle cx="105" cy="15" r="15">
					<animate attributeName="r" from="15" to="15" begin="0s" dur="0.8s" values="15;9;15" calcMode="linear" repeatCount="indefinite"></animate>
					<animate attributeName="fill-opacity" from="1" to="1" begin="0s" dur="0.8s" values="1;.5;1" calcMode="linear" repeatCount="indefinite"></animate>
				</circle>
			</svg>
		</div>
	</div>
</template>

<style lang="scss">
//@import '@/scss/variables.scss';

.vld-icon {
	svg {
		fill: #8e2b77;
	}
}

.vld-shown {
	overflow: hidden;
}

.vld-overlay {
	bottom: 0;
	left: 0;
	position: fixed;
	right: 0;
	top: 0;
	align-items: center;
	display: none;
	justify-content: center;
	overflow: hidden;
	z-index: 9999;
}

.vld-overlay.is-active {
	display: flex;
}

.vld-background {
	background: #252525;
	opacity: 0.1;
	backdrop-filter: blur(0px);
}

.vld-overlay .vld-background {
	bottom: 0;
	left: 0;
	position: absolute;
	right: 0;
	top: 0;
}

.vld-overlay .vld-icon,
.vld-parent {
	position: relative;
	//color: #0E92A6
}
</style>

<script setup>
import { inject } from 'vue';
const $loader = inject('$loader');
</script>
