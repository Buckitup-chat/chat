<script setup>
import { localDB } from '../../utils/db/localDB';
import { providePGlite } from '@electric-sql/pglite-vue';
import { onMounted, inject } from 'vue';


const providedDB = await localDB.init()

providePGlite(providedDB)

const $encryptionManager = inject('$encryptionManager');

console.log("Vaults", await $encryptionManager.getVaults())

onMounted(async () => {
  const $encryptionManager = inject('$encryptionManager');
  const vaults = await $encryptionManager.getVaults()
  console.log("Vaults", vaults)
});

</script>

<template>
  <slot></slot>
</template>
