export default {
  mounted() {
    this.handleEvent("put-flash", (params) => { this.putFlash(params) })
  },

  putFlash(params) {
    const flash = document.getElementById('flash-info')
    if (flash) {
      this.pushEvent('lv:clear-flash')
      flash.classList.remove("fade-out-flash")
    }

    this.pushEvent('put-flash', params)

    setTimeout(() => {
      const newFlash = document.getElementById('flash-info')
      if (newFlash) { newFlash.classList.add("fade-out-flash") }
    }, 200);

    setTimeout(() => { this.pushEvent('lv:clear-flash') }, 5000);
  }
};
