<!--
  Requirements:
  - Display a card with name and hash with flexible ordering
  - Accept name, hash, and publicKey as props
  - If publicKey is provided, check window.BuckitUp.contacts for matching contact
  - If contact is found, replace name with contact name and add italic styling
  - Recheck contacts periodically at random intervals (5-50 seconds)
  - Support custom styling for both name and hash elements
  - Support reverse display order via reverse prop
  - Use monospaced font for hash display
-->

<template>
  <div class="flex items-center">
    <template v-if="reverse">
      <div :class="[nameStyle, contactFound ? 'italic' : '']">{{ displayName }}</div>
      <span :class="['ml-1', hashStyle, 'font-mono']">[{{ hash }}]</span>
    </template>
    <template v-else>
      <span :class="[hashStyle, 'font-mono']">[{{ hash }}]</span>
      <div :class="['ml-1', nameStyle, contactFound ? 'italic' : '']">{{ displayName }}</div>
    </template>
  </div>
</template>

<script>
export default {
  name: 'Card',
  props: {
    name: {
      type: String,
      required: true
    },
    hash: {
      type: String,
      required: true
    },
    publicKey: {
      type: String,
      default: ''
    },
    reverse: {
      type: Boolean,
      default: false
    },
    nameStyle: {
      type: String,
      default: ''
    },
    hashStyle: {
      type: String,
      default: ''
    }
  },
  data() {
    return {
      contactFound: false,
      contactName: '',
      checkInterval: null
    }
  },
  computed: {
    displayName() {
      return this.contactFound ? this.contactName : this.name
    }
  },
  mounted() {
    this.checkContact()
    this.setupPeriodicCheck()
  },
  
  beforeUnmount() {
    this.clearCheckInterval()
  },
  methods: {
    checkContact() {
      if (!this.publicKey || !window.BuckitUp || !window.BuckitUp.contacts) {
        return
      }
      
      const contact = window.BuckitUp.contacts[this.publicKey]
      if (contact) {
        this.contactFound = true
        this.contactName = contact.name || contact
      }
    },
    
    setupPeriodicCheck() {
      this.clearCheckInterval()
      
      // Generate random interval between 5-50 seconds
      const randomMs = Math.floor(Math.random() * (50000 - 5000 + 1)) + 5000
      
      this.checkInterval = setInterval(() => {
        this.checkContact()
        // Set a new random interval after each check
        this.clearCheckInterval()
        this.setupPeriodicCheck()
      }, randomMs)
    },
    
    clearCheckInterval() {
      if (this.checkInterval) {
        clearInterval(this.checkInterval)
        this.checkInterval = null
      }
    }
  },
  watch: {
    publicKey() {
      this.checkContact()
    }
  }
}
</script>
