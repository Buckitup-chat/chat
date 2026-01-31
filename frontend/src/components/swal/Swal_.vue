<template>
	<div class="modal fade _swal_modal" ref="swalElement" id="swalElement" tabindex="-1" aria-labelledby="swalElement">
		<div class="modal-dialog">
			<div class="modal-content">
				<div class="modal-body" v-if="modalId && component">
					<component :is="component" :data="inputData"></component>
				</div>
			</div>
		</div>
	</div>
</template>

<style scss scoped>
._swal_modal {
	z-index: 1057; /* Set your desired z-index */
}
</style>

<script setup>
import { ref, defineAsyncComponent, onMounted, inject, shallowRef, computed } from 'vue';
import { Modal } from 'bootstrap';

const modalSizes = ['modal-sm', 'modal-lg', 'modal-xl'];
const $mitt = inject('$mitt');
const modalId = ref(null);
const modalInstance = ref(null);
const swalElement = ref(null);
const component = shallowRef(null);
const inputData = ref({});
let resolvePromise;

const modalRegistry = {
	confirm: {
		component: 'Swal_Confirm',
		modalClass: 'modal-sm',
	},
	delete_account: {
		component: 'Swal_DeleteAccount',
		modalClass: 'modal-sm',
	},
	delete_contact: {
		component: 'Swal_DeleteContact',
		modalClass: 'modal-sm',
	},

	copy_public_key: {
		component: 'Swal_CopyPublicKey',
		modalClass: 'modal-sm',
	},

	update_backup_share_delay: {
		component: 'Swal_UpdateBackupShareDelay',
		modalClass: 'modal-sm',
	},
};

onMounted(() => {
	$mitt.on('swal::open', open);
	$mitt.on('swal::close', close);
});

const open = async (data) => {
	try {
		const registry = modalRegistry[data.id];
		if (!registry) return;
		const options = { keyboard: true, focus: false };

		if (document.activeElement) document.activeElement.blur();

		if (registry.modalStatic) {
			options.backdrop = 'static';
			options.keyboard = false;
		}

		modalInstance.value = Modal.getOrCreateInstance(swalElement.value, options);
		swalElement.value.addEventListener('hidden.bs.modal', () => close());

		component.value = await defineAsyncComponent(() => import(`./views/${registry.component}.vue`));
		swalElement.value?.classList.remove(...modalSizes);
		if (registry.modalClass) {
			swalElement.value?.classList.add(registry.modalClass);
		}
		if (!modalId.value) {
			modalInstance.value.show();
		} else {
			modalInstance.value.handleUpdate();
		}
		modalId.value = data.id;
		inputData.value = data;

		const backdrops = document.querySelectorAll('.modal-backdrop');
		if (backdrops.length > 1) backdrops[backdrops.length - 1].classList.add('_swal_modal_backdrop');

		return new Promise((resolve) => {
			modalInstance.value.show();
			resolvePromise = resolve;
		});
	} catch (error) {
		console.error('swal modal open', error);
	}
};

const close = (res) => {
	if (document.activeElement) document.activeElement.blur();
	if (resolvePromise) resolvePromise(res);
	modalId.value = null;
	inputData.value = {};
	modalInstance.value.hide();
};

defineExpose({ open });
</script>
