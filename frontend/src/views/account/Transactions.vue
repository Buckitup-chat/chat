<template>
	<div v-for="tx in list" class="border-top py-2">
		<div class="d-flex justify-content-between">
			<div class="fw-bold d-flex align-items-center">
				<div v-if="tx.method === 'registerWithSign'">Activation</div>
				<div v-if="tx.method === 'addBackup'">Backup creation</div>
				<div v-if="tx.method === 'updateBackupDisabled'">Backup {{ tx.methodData.disabled ? 'disable' : 'enable' }}</div>
				<div v-if="tx.method === 'updateShareDisabled'">Backup share {{ tx.methodData.disabled ? 'disable' : 'enable' }}</div>
				<div v-if="tx.method === 'updateShareDelay'">Share delay update</div>
				<div v-if="tx.method === 'requestRecover'">Recover request</div>
			</div>
			<div class="text-end">
				{{ $date(tx.updatedAt).format('DD MMM HH:mm:ss ') }}
			</div>
		</div>

		<div class="d-flex justify-content-between small">
			<div class="">
				<a :href="$web3.blockExplorer + '/tx/' + tx.txHash" target="_blank" rel="noopener noreferrer">{{ $filters.txHashShort(tx.txHash) }}</a>
			</div>

			<div class="fw-bold text-end">
				<div class="text-secondary" v-if="tx.status === 'PROCESSING'">Confirming...</div>
				<div class="text-danger" v-if="tx.status === 'ERROR'">Error</div>
				<div class="text-success" v-if="tx.status === 'PROCESSED'">Confirmed</div>

				<router-link v-if="false && tx.methodData.tag" :to="'/recover?t=' + tx.methodData.tag" class="">
					{{ tx.methodData.tag }}
				</router-link>
			</div>
		</div>
	</div>
</template>

<script setup>
import { ref, onMounted, watch, inject, computed, onUnmounted } from 'vue';
import axios from 'axios';

const $user = inject('$user');
const $mitt = inject('$mitt');
const $web3 = inject('$web3');

const { list, onlyLast } = defineProps({
	list: { type: Array },
	onlyLast: {},
});
</script>
