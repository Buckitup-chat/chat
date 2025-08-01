<template>
	<!-- Header -->

	<div class="mb-2">
		<label class="form-label d-flex align-items-center" for="restoreDelay">
			Restore delay
			<InfoTooltip class="align-self-center ms-2" :content="'Restore delay info'" />
		</label>

		<div class="dropdown">
			<button class="btn btn-dark dropdown-toggle w-100" type="button" data-bs-toggle="dropdown" aria-expanded="false">
				{{ newDelay > 0 ? $filters.secondsToHMS(newDelay) : 'No delay' }}
			</button>
			<ul class="dropdown-menu">
				<li v-for="delay in delays">
					<a class="dropdown-item" href="#" @click="setDelay(delay)">
						{{ delay > 0 ? $filters.secondsToHMS(delay) : 'No delay' }}
					</a>
				</li>
			</ul>
		</div>
	</div>

	<div class="d-flex justify-content-center mt-3">
		<button type="button" class="btn btn-outline-dark" @click="cancel()">Cancel</button>
		<button type="button" class="btn btn-dark ms-2 px-4" @click="update()" :disabled="newDelay == data.currentDelay">Update</button>
	</div>
</template>

<script setup>
import { inject, ref, onMounted } from 'vue';

const $mitt = inject('$mitt');
const $user = inject('$user');

const delays = [0, 600, 3600, 86400, 259200, 604800, 1296000, 2592000];
const newDelay = ref(0);

const { data } = defineProps({
	data: { type: Object, required: true },
});

onMounted(() => {
	newDelay.value = data.currentDelay;
});

const setDelay = (delay) => {
	newDelay.value = delay;
};

function cancel() {
	$mitt.emit('swal::close', false);
}

function update() {
	$mitt.emit('swal::close', newDelay.value);
}
</script>

<style lang="scss">
@import '@/scss/variables.scss';

._warning {
	border-radius: $blockRadiusSm;
	padding: 1rem;
	background-color: rgba($warning, 0.2);
	text-align: center;

	._icon_warning {
		height: 2rem;
	}
}
</style>
