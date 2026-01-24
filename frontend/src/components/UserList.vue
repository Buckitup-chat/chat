<script setup lang="ts">
// import InternetIndicator from './InternetIndicator.vue'
import SyncStatus from './SyncStatus.vue'
import { ref, computed } from 'vue'
import { useLiveQuery } from '@electric-sql/pglite-vue'

// const name = ref('')

const filter = ref('')

const dbUsers = useLiveQuery(`SELECT * from users ORDER BY name ASC;`) //WHERE name LIKE $1;, //[filter.value ? `%${filter.value}%` : '%'])

const dbUsersLocal = useLiveQuery(`SELECT * from users_local;`)

const users: any = computed(() => dbUsers?.rows ?? [])

const usersLocal: any = computed(() => dbUsersLocal?.rows ?? [])

// const add = () => {
//   if (name.value.trim()) {
//     store.addUser(name.value.trim())
//     name.value = ''
//   }
// }
</script>

<template>
  <div class="p-6 max-w-2xl mx-auto">
    <div class="flex align-center mb-6 w-full justify-between">
      <SyncStatus :isSynced="usersLocal.value && usersLocal.value.length == 0" />
    </div>

    <div class="_search mb-1">
      <div class="_input_search">
        <div class="_icon_search"></div>
        <input class="" type="text" v-model="filter" autocomplete="off" placeholder="Search..." />

        <div class="_icon_times" v-if="filter" @click="filter = ''"></div>
      </div>
    </div>

    <ul v-if="users.value && users.value?.length > 0" class="_users_list">
      <li v-for="user in users.value" :key="5" class="_users_list_item">
        <div v-if="user.name.includes(filter)">
          <div>
            {{ user.name }}

            <span class="_icon_check" v-if="user.synced">
              &check;
            </span>

            <span class="_icon_wait" v-if="!user.synced">
              &#x29D6;
            </span>
          </div>

          <!-- <div class="text-xs text-gray-500 font-mono">{{ user.pub_key }}</div> -->
        </div>

      </li>
    </ul>

    <!-- <div class="flex gap-2 ">
      <input v-model="name" placeholder="Name" class="border p-3 flex-1 rounded" />

      <button @click="add" class="bg-green-600 text-white px-6 py-3 rounded font-semibold">
        Add
      </button>
    </div> -->
  </div>
</template>

<style lang="scss" scoped>
@import '@/scss/variables.scss';
@import '@/scss/breakpoints.scss';

._users_list {
  display: flex;
  flex-direction: column;
  overflow: hidden;
  list-style-type: none;

  &._has_contacts {
    flex-grow: 1;
    height: calc(100vh - 3rem);
  }

  ._list {
    flex-grow: 1;
    overflow-y: auto;

    ._contact {
      display: flex;
      align-items: center;
      padding: 0.5rem;
      width: 100%;
      cursor: pointer;
      border-radius: $blockRadiusSm;

      &:hover {
        background-color: lighten($black, 90%);
      }

      &._selected {
        background-color: lighten($black, 85%);
      }
    }
  }
}
</style>