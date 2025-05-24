<script setup>
import { ref, onMounted, watch } from "vue"

// Define props (without type checking)
const props = defineProps({
  unixtime: Number
})

// Create a reactive string to hold the formatted timestamp
const formattedTime = ref("")

// Function to update the timestamp display
const updateTimestamp = () => {
  if (!props.unixtime) return

  const date = new Date(props.unixtime * 1000)
  const timeString = date.toLocaleTimeString()
  const dateString = date.toLocaleDateString()
  formattedTime.value = `${timeString} ${dateString}`
}

// Update the timestamp when the component is mounted
onMounted(() => {
  updateTimestamp()
})

// Watch for changes to the unixtime prop and update the display
watch(() => props.unixtime, () => {
  updateTimestamp()
})
</script>

<template>
  {{ formattedTime }}
</template>