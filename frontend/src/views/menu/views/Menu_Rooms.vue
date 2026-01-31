<template>    
    <Contacts_List @select="select" :selected="selected" v-if="$user.account.rooms?.length" />

    <div class="fs-5 text-center" v-if="!$user.account.rooms?.length">
        <p>Your list is empty</p>
    </div>    
</template>

<script setup>
import Contacts_List from '@/views/contacts/Contacts_List.vue';
import { ref, inject } from 'vue';

const $router = inject('$router')
const $user = inject('$user')

const selected = ref([])

const select = (roomId) => {    
    selected.value = [address]
    $router.push({ name: 'room', params: { roomId } })
}

</script>
