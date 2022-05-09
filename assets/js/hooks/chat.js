export const hooks = {
  mounted() {
    console.log(2222)
    this.scrollToBottom();
  },
  updated() {
    console.log(3333)
    this.scrollToBottom();
  },
  scrollToBottom() {
    Promise.all(Array.from(document.images).filter(img => !img.complete).map(img => new Promise(resolve => { img.onload = img.onerror = resolve; }))).then(() => {
      this.el.scroll({top: this.el.scrollHeight, behavior: 'smooth'});
    });
  }
}
