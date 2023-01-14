export default {
  mounted() {
    const androidMediaFileinput = this.el
    const ref = androidMediaFileinput.dataset.ref
    const fileInput = document.getElementById(ref)

    this.el.addEventListener('change', () => {
      this.uploadTo(fileInput, 'file', this.el.files)
    })
  }
}
