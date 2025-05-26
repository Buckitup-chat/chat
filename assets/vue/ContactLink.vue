<!--
  Requirements:
  - Accept publicKey as prop
  - If publicKey is present in window.BuckitUp.contacts and address is present, becomes clickable link
  - Otherwise stays as a simple button
  - Support slot content to keep contents in LiveView heex template
-->

<template>
  <a 
    v-if="hasValidContact" 
    :href="`/contact/${contactAddress}`"
    class="inline-block">
    <slot><!-- Slot content for link --></slot>
  </a>
  <button v-else type="button" class="inline-flex items-center p-0 bg-transparent">
    <slot>
      <!-- Fallback content if slot is empty -->
    </slot>
  </button>
</template>

<script>
export default {
  name: 'ContactLink',
  props: {
    publicKey: {
      type: String,
      default: ''
    }
  },
  data() {
    return {
      hasValidContact: false,
      contactAddress: '',
      checkInterval: null
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
        this.hasValidContact = false
        return
      }
      
      const contact = window.BuckitUp.contacts[this.publicKey]
      if (contact && contact.address) {
        this.hasValidContact = true
        this.contactAddress = contact.address
      } else {
        this.hasValidContact = false
      }
    },
    
    setupPeriodicCheck() {
      this.clearCheckInterval()
      
      // Generate random interval between 5-50 seconds (similar to Card.vue pattern)
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
