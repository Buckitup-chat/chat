// JS Hook for storing some state in sessionStorage in the browser.
// The server requests stored data and clears it when requested.
export const hooks = {
  mounted() {
    this.handleEvent("store", (obj) => this.store(obj))
    this.handleEvent("clear", (obj) => this.clear(obj))
    this.handleEvent("restore", (obj) => this.restore(obj))
  },

  store(obj) {
    localStorage.setItem(obj.key, obj.data)
  },

  restore(obj) {
    var data = localStorage.getItem(obj.key)
    this.pushEvent(obj.event, data)
  },

  clear(obj) {
    localStorage.removeItem(obj.key)
  }
}
