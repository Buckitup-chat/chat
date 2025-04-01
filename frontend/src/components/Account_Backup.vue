<template>
	<div>
		<div class="text-secondary mb-2">Safeguard access to your profile during unforeseen events, and securely back up your key to your reliable network.</div>

		<div class="_divider">
			Select your backup option
			<InfoTooltip class="align-self-center ms-2" :content="'Select your backup option info'" />
		</div>

		<div class="_input_block mt-2 d-flex _pointer p-3">
			<div class="_icon_buckitup_circle _select_icon"></div>
			<div>
				<div class="fw-bold fs-5">BuckitUp network</div>
				<div class="text-secondary">Store your key parts securely (irreversible) within the app, through your trusted network, allowing easy access offline.</div>
			</div>
		</div>

		<div class="_input_block mt-2 d-flex _pointer p-3" @click="createShare()">
			<div class="_icon_gnossis_chain _select_icon"></div>
			<div>
				<div class="d-flex justify-content-between align-items-center">
					<div class="fw-bold fs-5">Gnosis blockchain</div>

					<div class="_icon_wifi" :class="[$user.isOnline ? 'bg-success' : 'bg-danger']"></div>
				</div>

				<div class="text-secondary">Secure your key parts with additional security features on the decentralised network.</div>
			</div>
		</div>
		<div class="_input_block mt-2 d-flex p-2 px-3" v-if="showLocal">
			<div class="_icon_buckup_devices _select_icon"></div>
			<div class="">
				<div class="fw-bold fs-5 _pointer" @click="exportLocally = !exportLocally">Export locally</div>

				<div class="text-secondary _pointer" @click="exportLocally = !exportLocally">Save backup file on your device, make sure to set secured password</div>

				<template v-if="exportLocally">
					<div class="mb-2 mt-2">
						<div class="form-check form-switch mb-2">
							<input class="form-check-input" type="checkbox" role="switch" id="setpassword" v-model="protect" />
							<label class="form-check-label d-flex align-items-center _pointer" for="setpassword">
								Password protect
								<InfoTooltip class="align-self-center ms-2" :content="'Password info. Provide strong password'" />
							</label>
						</div>
						<template v-if="protect">
							<div class="d-flex">
								<form autocomplete="off" class="w-100">
									<input
										:type="showPassword ? 'text' : 'password'"
										id="password"
										v-model="password"
										class="form-control"
										placeholder="password from your backup"
										autocomplete="new-password"
										readonly
										@focus="$event.target.removeAttribute('readonly')"
										:class="[dirty && (passwordErrors.length ? 'is-invalid' : 'is-valid')]"
									/>
								</form>
								<button class="btn btn-dark ms-2 d-flex align-items-center" @click="showPassword = !showPassword">
									<i class="bg-white" :class="[showPassword ? '_icon_eye_cross' : '_icon_eye']"> </i>
								</button>
							</div>
							<ul class="small" v-if="dirty && passwordErrors.length">
								<li v-for="error in passwordErrors" :key="error">{{ error }}</li>
							</ul>
						</template>
					</div>

					<button type="button" class="btn btn-dark d-flex justify-content-center align-items-center w-100" @click="backup()">Download</button>
				</template>
			</div>
		</div>
	</div>
</template>

<style lang="scss" scoped>
._select_icon {
	height: 3rem;
	min-width: 3rem;
	width: 3rem;
	margin-right: 1rem;
	margin-top: 1rem;
}
._export_locally {
	margin-left: 4rem;
	width: 100%;
}
</style>

<script setup>
import { inject, ref, watch, computed } from 'vue';

const $enigma = inject('$enigma');
const $user = inject('$user');
const $swal = inject('$swal');
const $router = inject('$router');
const $mitt = inject('$mitt');

const protect = ref(true);
const showPassword = ref(true);
const password = ref();
const dirty = ref();
const exportLocally = ref();

const { showLocal } = defineProps({ showLocal: { type: Boolean } });

const emit = defineEmits(['backup']);

watch(
	() => protect.value,
	(val) => {
		if (!val) {
			password.value = null;
			showPassword.value = true;
			dirty.value = false;
		}
	},
);

watch(
	() => password.value,
	(val) => {
		if (val) {
			password.value = password.value.replaceAll(' ', '');
			if (val.length > 3) dirty.value = true;
		}
	},
);

const createShare = () => {
	if (!$user.checkOnline()) return;
	$mitt.emit('modal::close');
	$router.push({ name: 'backup_create' });
};

const backup = async () => {
	dirty.value = true;
	if (passwordErrors.value.length) return;

	const backup = {
		account: {
			publicKey: $user.account.publicKey,
			privateKey: $user.account.privateKey,
		},
		accountInfo: $user.accountInfo,
		contacts: $user.contacts,
	};
	const jsonString = JSON.stringify(backup, null, 2);

	let backupString;
	if (password.value) {
		const base64PlainData = btoa(jsonString);
		const base64Password = btoa(password.value);
		backupString = $enigma.encryptData(base64PlainData, base64Password);
	} else {
		backupString = jsonString;
	}

	const blob = new Blob([backupString], { type: 'text/plain' });
	const url = URL.createObjectURL(blob);
	const a = document.createElement('a');
	a.href = url;
	a.download = generateBackupName($user.accountInfo.name);
	document.body.appendChild(a);
	a.click();
	document.body.removeChild(a);
	URL.revokeObjectURL(url);

	emit('backup');

	showPassword.value = true;
	password.value = null;
};

function generateBackupName(rawName) {
	const now = new Date();
	const yyyy = now.getFullYear();
	const mm = String(now.getMonth() + 1).padStart(2, '0');
	const dd = String(now.getDate()).padStart(2, '0');
	const datePart = `${yyyy}_${mm}_${dd}`;
	// Remove all characters except letters, digits, underscores, and hyphens, spaces
	const safeName = rawName.replace(/[^a-zA-Z0-9_-]/g, '');
	return `backup_${datePart}_${safeName}${password.value ? '_encrypted' : '_raw'}.bukitup`;
}

const passwordErrors = computed(() => {
	const errors = [];
	if (!protect.value) return errors;

	if (password.value.length < 10) errors.push('Must be at least 10 characters long.');
	if (!/[A-Z]/.test(password.value)) errors.push('Must contain an uppercase letter (A-Z).');
	if (!/[a-z]/.test(password.value)) errors.push('Must contain a lowercase letter (a-z).');
	if (!/\d/.test(password.value)) errors.push('Must contain a digit (0-9).');
	if (!/[!@#$%^&*(),.?":{}|<>]/.test(password.value)) errors.push('Must contain a special character (e.g. !@#$%^&*).');

	return errors;
});
</script>
