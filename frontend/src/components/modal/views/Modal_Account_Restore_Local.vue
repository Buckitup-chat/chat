<template>
	<div>
		<div class="_divider mt-3">
			Upload your backup file
			<InfoTooltip class="align-self-center ms-2" :content="'Upload your backup file info'" />
		</div>

		<div class="row justify-content-center gx-2 mt-3">
			<div class="col-md-20">
				<button type="button" class="btn btn-dark w-100" @click="fileInput.click()">Upload</button>
			</div>
			<input type="file" ref="fileInput" accept=".bukitup" style="height: 0px; width: 0px" @change="handleRestore" :key="fileInputKey" />
		</div>

		<template v-if="fileString && requestDecrypt">
			<div class="_divider mt-3">
				Decrypt backup
				<InfoTooltip class="align-self-center ms-2" :content="'Decrypt backup info'" />
			</div>
			<div class="_input_block w-100 px-3 mt-2 mb-2">
				<label for="password" class="form-label d-flex align-items-center">
					Password
					<InfoTooltip class="align-self-center ms-2" :content="'Password info'" />
				</label>

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
						/>
					</form>

					<button class="btn btn-dark ms-2 d-flex align-items-center" @click="showPassword = !showPassword">
						<i class="bg-white" :class="[showPassword ? '_icon_eye_cross' : '_icon_eye']"> </i>
					</button>
				</div>
			</div>

			<div class="row justify-content-center gx-2 mt-3">
				<div class="col-md-20">
					<button class="btn btn-dark w-100" :disabled="!password" @click="decrypt()">Decrypt and restore</button>
				</div>
			</div>
		</template>
	</div>
</template>

<style lang="scss" scoped></style>

<script setup>
import { ref, inject } from 'vue';
import errorMessage from '@/utils/errorMessage';

const $web3 = inject('$web3');
const $swal = inject('$swal');
const $user = inject('$user');
const $mitt = inject('$mitt');
const $enigma = inject('$enigma');
const $router = inject('$router');
const $swalModal = inject('$swalModal');
const $encryptionManager = inject('$encryptionManager');

const fileString = ref();
const requestDecrypt = ref();
const password = ref();
const showPassword = ref();

const fileInput = ref();
const fileInputKey = ref(0);

const handleRestore = async (event) => {
	fileString.value = null;
	requestDecrypt.value = null;

	const file = Array.from(event.target.files)[0];
	const reader = new FileReader();

	reader.onload = async (event) => {
		fileString.value = event.target.result;
		let data;
		try {
			data = JSON.parse(fileString.value);
		} catch (error) {
			console.error('handleRestore', error);
		}

		if (!data) {
			requestDecrypt.value = true;
		} else {
			await applyBackup(data);
		}
	};
	reader.readAsText(file);
};

const decrypt = async () => {
	try {
		const base64Password = btoa(password.value);
		const decryptedBase64 = $enigma.decryptData(fileString.value, base64Password);
		const jsonString = atob(decryptedBase64);
		const data = JSON.parse(jsonString);
		await applyBackup(data);
	} catch (error) {
		console.error(error);
		$swal.fire({
			icon: 'error',
			title: 'Unable to decrypt',
			text: 'Check if backup valid and password is correct', //
			footer: errorMessage(error),
			timer: 15000,
		});
	}
};

const applyBackup = async (data) => {
	try {
		const account = await $user.generateAccount(data.account.privateKey);
		const accountInfo = data.accountInfo;

		const idx = $user.vaults.findIndex((a) => a.publicKey === account.publicKey);
		if (idx > -1) {
			const confirmed = await $swalModal.value.open({
				id: 'confirm',
				title: 'Account restore',
				content: `
                    Account <strong>${accountInfo.name}</strong> already present on this device.
                    <br> Are you sure you want to replace it with one from backup?
                    `,
			});
			if (!confirmed) {
				fileInput.value = null;
				fileInputKey.value++;
				return;
			}

			await $encryptionManager.removeVault($user.vaults[idx].vaultId);

			$user.vaults = await $encryptionManager.getVaults();
		}

		await $encryptionManager.createVault({
			keyOptions: {
				username: accountInfo.name,
				displayName: accountInfo.name,
			},
			address: account.address,
			publicKey: account.publicKey,
			avatar: accountInfo.avatar,
			notes: accountInfo.notes,
		});

		$user.account = account;

		await $user.openStorage({
			accountInfo: {
				name: accountInfo.name,
				notes: accountInfo.notes,
				avatar: accountInfo.avatar,
			},
		});

		if (data.contacts && data.contacts.length) {
			//await $user.initializeContacts(data.contacts);
		}

		$mitt.emit('account::created');

		$router.replace({ name: 'account_info' });
		$mitt.emit('modal::close');
	} catch (error) {
		$swal.fire({
			icon: 'error',
			title: 'Restore error',
			text: errorMessage(error),
			timer: 15000,
		});
	}
};
</script>
