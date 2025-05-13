<template>
	<div class="modal fade" ref="modalElement" id="modalElement" tabindex="-1" aria-labelledby="modalElement">
		<div class="modal-dialog" :class="{ 'modal-dialog-scrollable': scrollable }">
			<div class="modal-content">
				<div class="modal-header" v-if="$slots.header">
					<slot name="header"></slot>
				</div>
				<div class="modal-body" :class="currentModal.bodyClass" v-if="modalId && component">
					<template v-if="currentModal.header">
						<!-- Header -->
						<div class="d-flex align-items-center justify-content-between mb-2">
							<div class="d-flex align-items-center">
								<div class="_modal_icon bg-black me-2" :class="[currentModal.icon]"></div>
								<div>
									<div class="fs-5">{{ currentModal.title }}</div>
								</div>
							</div>
							<div class="d-flex">
								<div class="btn _icon_times bg-dark" @click="closeModal()"></div>
							</div>
						</div>
						<!--div class="border-bottom w-100 mt-3 mb-2"></div-->
					</template>

					<component :is="component" :input-data="inputData"></component>
				</div>
				<div class="modal-footer" v-if="$slots.footer">
					<slot name="footer"></slot>
				</div>
			</div>
		</div>
	</div>
</template>

<style lang="scss" scoped>
._modal_icon {
	height: 1.3rem;
	width: 1.3rem;
}
</style>

<script setup>
import { Modal } from 'bootstrap';
import { ref, shallowRef, onMounted, defineAsyncComponent, inject, watch, computed } from 'vue';

const $mitt = inject('$mitt');

const scrollable = ref(null);
const modal = ref(null);
const modalId = ref(null);
const modalElement = ref(null);
const modalSizes = ['modal-sm', 'modal-lg', 'modal-xl'];
let resolvePromise;

const modalRegistry = {
	add_contact: {
		header: true,
		modalStatic: true,
		component: 'Modal_AddContact',
		modalClass: 'modal-sm',
		title: 'Add contact',
		icon: '_icon_profile',
	},
	add_contact_handshake: {
		header: false,
		component: 'Modal_QrHandshake',
		modalClass: 'modal-md',
	},
	save_contact: {
		header: false,
		component: 'Modal_SaveContact',
		modalClass: 'modal-md',
	},

	account_create: {
		header: true,
		component: 'Modal_Account_Create',
		modalClass: 'modal-sm',
		title: 'Create account',
		icon: '_icon_profile',
	},

	account_backup: {
		header: true,
		component: 'Modal_Account_Backup',
		modalClass: 'modal-sm',
		title: 'Account Backup',
		icon: '_icon_backups',
	},

	account_dxos_invite: {
		header: true,
		component: 'Modal_Account_Invite',
		modalClass: 'modal-sm',
		title: 'Invite other device',
		icon: '_icon_reload',
	},

	account_connect: {
		header: true,
		component: 'Modal_Account_Connect',
		modalClass: 'modal-sm',
		title: 'Connect to other device',
		icon: '_icon_reload',
	},

	account_activate: {
		header: false,
		component: 'Modal_Account_Activate',
		modalClass: 'modal-sm',
		title: 'Account Activation',
		icon: '_icon_profile',
		bodyClass: 'p-0',
	},

	account_restore_shares: {
		header: true,
		component: 'Modal_Account_Restore_Shares',
		modalClass: 'modal-md',
		title: 'Restore account',
		icon: '_icon_shares',
	},

	account_restore_local: {
		header: true,
		component: 'Modal_Account_Restore_Local',
		modalClass: 'modal-sm',
		title: 'Restore account',
		icon: '_icon_backups',
	},

	signin: {
		header: false,
		component: 'Modal_SignIn',
		modalClass: 'modal-md',
	},
	logout: {
		header: true,
		component: 'Modal_Logout',
		modalClass: 'modal-sm',
		title: 'Accounts',
		icon: '_icon_logout',
	},

	auth: {
		header: false,
		component: 'Modal_Auth',
		modalClass: 'modal-md',
	},

	contacts: {
		header: true,
		component: 'Modal_Contacts',
		modalClass: 'modal-md',
		title: 'Verified contacts',
		icon: '_icon_contacts',
	},
};

onMounted(() => {
	$mitt.on('modal::open', open);
	$mitt.on('modal::close', close);
});

const component = shallowRef(null);
const inputData = ref({});

const currentModal = computed(() => {
	return modalId.value ? modalRegistry[modalId.value] : null;
});

async function open(data) {
	try {
		const registry = modalRegistry[data?.id];
		if (!registry) return;
		if (document.activeElement) document.activeElement.blur();

		//if ($user.auth && id === 'login') return
		//if (modalRegistry[id]?.auth && !$user.auth) {
		//    id = 'login'
		//} else {
		//    inputData.value = data
		//}

		const options = { keyboard: true, focus: false };

		if (registry?.modalStatic) {
			options.backdrop = 'static';
			options.keyboard = false;
		}

		modal.value = Modal.getOrCreateInstance(modalElement.value, options);
		modalElement.value.addEventListener('hidden.bs.modal', () => close());

		component.value = await defineAsyncComponent(() => import(`./views/${registry.component}.vue`));
		modalElement.value?.classList.remove(...modalSizes);
		if (registry.modalClass) {
			modalElement.value?.classList.add(registry.modalClass);
		}

		if (!modalId.value) {
			modal.value.show();
		} else {
			modal.value.handleUpdate();
		}
		inputData.value = data;
		modalId.value = data.id;

		return new Promise((resolve) => {
			modal.value.show();
			resolvePromise = resolve;
		});
	} catch (error) {
		console.log('modal open', error);
	}
}

const close = (res) => {
	if (document.activeElement) document.activeElement.blur();

	if (resolvePromise) resolvePromise(res);
	inputData.value = {};
	if (modalId.value) {
		modalId.value = null;
		modal.value.hide();
	}
};
defineExpose({ open, close });

function closeModal() {
	$mitt.emit('modal::close');
}
</script>
