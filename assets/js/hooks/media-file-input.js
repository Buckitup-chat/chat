export default {
  mounted() {
    const mediaFileInput = this.el
    const ref = mediaFileInput.dataset.ref
    const fileInput = document.getElementById(ref)

    this.el.addEventListener('change', () => {
      this.uploadTo(fileInput, 'file', this.el.files)
    })
  }
}
