<template>    
    <router-link :to="{ name: 'backup_list' }" custom v-slot="{ isActive, navigate }">
        <div class="_sub_menu_btn" :class="{ '_active': isActive }" @click="select(navigate)">
            <div class="_i_block">
                <i class="_icon_backups" :class="{ '_active': isActive }"></i>
            </div>                    
            <div>                        
                My backups                       
            </div>
        </div>
    </router-link>

    <router-link :to="{ name: 'backup_myshares' }" custom v-slot="{ isActive, navigate }">
        <div class="_sub_menu_btn" :class="{ '_active': isActive }" @click="select(navigate)">
            <div class="_i_block">
                <i class="_icon_shares" :class="{ '_active': isActive }"></i>
            </div>                    
            <div>                        
                My shares                       
            </div>
        </div>
    </router-link>

    <router-link :to="{ name: 'backup_restore' }" custom v-slot="{ isActive, navigate }">
        <div class="_sub_menu_btn" :class="{ '_active': isActive }" @click="select(navigate)">
            <div class="_i_block">
                <i class="_icon_restore" :class="{ '_active': isActive }"></i>
            </div>                    
            <div>                        
                Restore secret                        
            </div>
        </div>
    </router-link>    
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
@import '@/scss/breakpoints.scss';

</style>

<script setup>

import { inject } from 'vue';
const $menuOpened = inject('$menuOpened')

const select = (navigate) => {
    $menuOpened.value = false
    navigate()
}

</script>
