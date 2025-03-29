<template>
	<FullContentBlock v-if="contact">
		<template #header>
			<div class="d-flex align-items-center justify-content-between w-100 pe-3">
				<div class="fw-bold fs-5">Contact</div>
				<button class="btn btn-dark rounded-pill ms-1 d-flex align-items-center justify-content-center p-2 px-3" @click="$mitt.emit('modal::open', { id: 'add_contact_handshake' })">
					<i class="_icon_plus bg-white"></i>
					<span class="ms-2">Add</span>
				</button>
			</div>
		</template>
		<template #content>
			<div class="_full_width_block">
				<Account_Info :account-in="contact" @update="updateContact" />

				<div class="text-danger text-center fw-bold mt-2" v-if="contact.hidden">Contact is hidden in your list of contacts</div>

				<div class="d-flex justify-content-center align-items-center mt-4 mb-3">
					<button type="button" class="btn btn-dark rounded-pill _action_btn" v-tooltip="'Chat with contact'">
						<i class="_icon_chats bg-white"></i>
					</button>

					<button type="button" class="btn btn-dark rounded-pill _action_btn" v-tooltip="'Add contact to room'">
						<i class="_icon_rooms bg-white"></i>
					</button>

					<button
						type="button"
						class="btn btn-dark rounded-pill _action_btn"
						@click="toggleHidden()"
						v-tooltip="!contact.hidden ? 'Hide contact from list' : 'Restore (Unhide) contact in list'"
					>
						<i class="_icon_eye_cross bg-white" v-if="!contact.hidden"></i>
						<i class="_icon_eye bg-white" v-else></i>
					</button>
				</div>
			</div>
		</template>
	</FullContentBlock>
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
@import '@/scss/breakpoints.scss';

._full_width_block {
	max-width: 30rem;
	width: 100%;
}

._action_btn {
	padding: 0.8rem;
	@include media-breakpoint-up(sm) {
		padding: 1.2rem;
	}
	margin-left: 0.3rem;
	margin-right: 0.3rem;
	i {
		height: 1.5rem;
		width: 1.5rem;
	}
}
</style>

<script setup>
import { ref, onMounted, watch, inject, computed, nextTick } from 'vue';
import Account_Info from '@/components/Account_Info.vue';
import FullContentBlock from '@/components/FullContentBlock.vue';
import errorMessage from '@/utils/errorMessage';
import dayjs from 'dayjs';

const $user = inject('$user');
const $swal = inject('$swal');
const $route = inject('$route');
const $router = inject('$router');
const $swalModal = inject('$swalModal');
const $mitt = inject('$mitt');
const $enigma = inject('$enigma');

onMounted(async () => {
	if (!contact.value) {
		return $router.push({ name: 'account_info' });
	}
});

const contact = computed(() => {
	return $user.contacts.find((e) => e.address === $route.params.address);
});

const listedContacts = computed(() => {
	return $user.contacts.filter((contact) => !contact.hidden);
});

async function updateContact(updatedContact) {
	try {
		const contactDx = $user.contactsDx.find((e) => e.id === updatedContact.id);
		if (contactDx) {
			if (contact.value.name !== updatedContact.name) {
				contactDx.name = $enigma.encryptDataSync(updatedContact.name, $user.account.privateKey);
				contactDx.updatedAt = dayjs().valueOf();
			}
			if (contact.value.avatar !== updatedContact.avatar) {
				contactDx.avatar = $enigma.encryptDataSync(updatedContact.avatar, $user.account.privateKey);
				contactDx.updatedAt = dayjs().valueOf();
			}
			if (contact.value.notes !== updatedContact.notes) {
				contactDx.notes = $enigma.encryptDataSync(updatedContact.notes, $user.account.privateKey);
				contactDx.updatedAt = dayjs().valueOf();
			}
		}
	} catch (error) {
		console.log(error);
		$swal.fire({
			icon: 'error',
			title: 'Saving',
			text: errorMessage(error),
			timer: 15000,
		});
	}
}

const toggleHidden = async () => {
	const contactDx = $user.contactsDx.find((e) => e.id === contact.value.id);
	if (contactDx) {
		let hide;
		if (!contact.value.hidden) {
			if (!(await $swalModal.value.open({ id: 'delete_contact' }))) return;
			hide = true;
		}

		contactDx.hidden = $enigma.encryptDataSync(!contact.value.hidden, $user.account.privateKey);
		contactDx.updatedAt = dayjs().valueOf();

		if (hide) {
			await new Promise((resolve) => setTimeout(resolve, 300));

			if (listedContacts.value.length) {
				$router.push({ name: 'contact', params: { address: listedContacts.value[0].address } });
			} else {
				if (window.history.length > 1) {
					$router.go(-1); // ✅ Go back if history exists
				} else {
					$router.push({ name: 'home' }); // ✅ Otherwise, go home
				}
			}
		}
	}
};
</script>
