<template>
	<div class="_account">
		<div class="_avatar">
			<Avatar :name="acc.address" variant="bauhaus" v-if="acc.address && !acc?.avatar" />
			<img v-if="acc?.avatar" :src="mediaUrl(acc.avatar, defaultAvatar)" @error="(event) => (event.target.src = defaultAvatar)" />
		</div>
		<div class="_info">
			<div class="d-flex">
				<div class="_name" v-if="acc.name">
					<span v-if="acc.highlightedName" v-html="acc.highlightedName"></span>
					<span v-else>{{ acc.name }}</span>
				</div>
				<div class="_pubk" v-if="shortCode">[{{ shortCode }}]</div>
			</div>

			<div class="_notes" v-if="acc.notes">
				<span v-if="acc.highlightedNotes" v-html="acc.highlightedNotes"></span>
				<span v-else>{{ acc.notes }}</span>
			</div>
		</div>
	</div>
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
@import '@/scss/breakpoints.scss';

._account {
	display: flex;
	align-items: center;
	._avatar {
		display: flex;
		align-items: center;
		justify-content: center;
		height: 2.5rem;
		width: 2.5rem;
		border-radius: 50%;
		overflow: hidden;
		margin-right: 0.6rem;
		flex-shrink: 0; // Prevents shrinking when text overflows
		img,
		svg {
			height: 100%;
			width: 100%;
			border-radius: 30rem;
			object-fit: cover;
		}
	}
	._info {
		flex-grow: 1; // Allows it to expand within the container
		min-width: 0; // Ensures text truncation works
		._name {
			font-weight: 500;
			font-size: 0.9rem;
			white-space: nowrap;
			overflow: hidden;
			text-overflow: ellipsis;
			max-width: 100%; // Ensures truncation works properly
			display: block; // Ensures proper alignment
		}
		._pubk {
			font-weight: 400;
			font-size: 0.9rem;
			color: $grey_dark;
			margin-left: 0.4rem;
		}
		._notes {
			color: $grey_dark2;
			font-size: 0.85rem;
			white-space: nowrap;
			overflow: hidden;
			text-overflow: ellipsis;
			max-width: 100%; // Ensures truncation works properly
			display: block; // Ensures proper alignment
		}
	}
}
</style>

<script setup>
import { mediaUrl } from '@/utils/mediaUrl';
import Avatar from 'vue-boring-avatars';
import { inject, computed } from 'vue';

const defaultAvatar = '/img/profile.webp';
const $user = inject('$user');
const $enigma = inject('$enigma');

const { account, self } = defineProps({
	account: { type: Object },
	self: { type: Boolean },
});

const acc = computed(() => {
	return self ? { ...$user.account, ...$user.accountInfo } : account;
});
const shortCode = computed(() => {
	if (acc.value.publicKey) return $enigma.shortCode($enigma.stringToBase64(acc.value.publicKey));
});
</script>
