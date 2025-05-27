<template>
	<div>
		<div class="d-flex justify-content-between mb-2">
			<div class="w-100" v-if="contact">
				<Account_Item :account="contact" />
			</div>

			<div class="fw-bold mb-1" v-else>
				Trusted partie <span v-if="data.length > 1">{{ data.idx + 1 }}</span>
			</div>

			<i class="_icon_times bg-dark _pointer" @click="emit('removeWallet')"></i>
		</div>

		<div class="row gx-2">
			<div class="col-md-30 col-lg-20" v-if="data.advanced">
				<div class="mb-2">
					<label class="form-label d-flex align-items-center" for="address">
						Wallet address
						<InfoTooltip class="align-self-center ms-2" :content="'Wallet address info'" />
					</label>

					<input
						type="text"
						id="tag"
						v-model="wallet.address"
						class="form-control"
						placeholder="wallet address of trusted partie"
						:class="[wallet.dirty && (wallet.invalid ? 'is-invalid' : 'is-valid')]"
					/>

					<div class="small text-danger" v-if="wallet.dirty && wallet.invalid">
						{{ wallet.invalid }}
					</div>
				</div>
			</div>

			<div class="small text-danger" v-if="!data.advanced && wallet.dirty && wallet.invalid">
				{{ wallet.invalid }}
			</div>

			<div class="col-md-30 col-lg-10" v-if="data.advanced">
				<div class="mb-2">
					<label class="form-label d-flex align-items-center" for="restoreDelay">
						Restore delay
						<InfoTooltip class="align-self-center ms-2" :content="'Restore delay info'" />
					</label>

					<div class="dropdown">
						<button class="btn btn-dark dropdown-toggle w-100" type="button" data-bs-toggle="dropdown" aria-expanded="false">
							{{ wallet.delay > 0 ? $filters.secondsToHMS(wallet.delay) : 'No delay' }}
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
			</div>

			<div class="col-30">
				<div class="mb">
					<label class="form-label d-flex align-items-center" for="comment">
						Message for trusted partie
						<InfoTooltip class="align-self-center ms-2" :content="'Restore delay info'" />
						<span class="small ms-2 text-secondary" v-if="wallet.message && maxMessageLength > wallet.message.length">{{ maxMessageLength - wallet.message.length }} characters left</span>
						<span class="small ms-2 text-secondary" v-if="!wallet.message">{{ maxMessageLength }} characters max</span>
					</label>
					<textarea type="text" id="comment" v-model="wallet.message" class="form-control" placeholder="any message for trusted partie, visible only to partie, optional" rows="2"></textarea>
				</div>
			</div>
		</div>
	</div>
</template>

<script setup>
import { watch, computed, inject } from 'vue';
import Account_Item from '@/components/Account_Item.vue';
const maxMessageLength = 150;
const delays = [0, 600, 3600, 86400, 259200, 604800, 1296000, 2592000];
const $user = inject('$user');

const { wallet, data } = defineProps({
	wallet: { typ: Object, required: true },
	data: { typ: Object, required: true },
});

const emit = defineEmits(['setWallet', 'removeWallet']);

const setDelay = (delay) => {
	wallet.delay = delay;
	setWallet();
};

const setWallet = () => {
	emit('setWallet', { wallet, idx: data.idx });
};

const contact = computed(() => {
	try {
		return $user.contacts.find((c) => c.address.toLowerCase() === wallet.address.toLowerCase());
	} catch (error) {}
});

watch(
	() => wallet.address,
	() => {
		if (wallet.address) wallet.address = wallet.address.trim();
		setWallet();
	},
);

watch(
	() => wallet.message,
	(newValue) => {
		if (newValue && newValue.length > maxMessageLength) {
			wallet.message = newValue.slice(0, maxMessageLength);
		}
		setWallet();
	},
);
</script>
