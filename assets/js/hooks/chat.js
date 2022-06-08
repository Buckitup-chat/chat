export const hooks = {
  mounted() {
    this.pending = this.page();
    this.setScrollTop();

    this.el.addEventListener("scroll", e => {
      if (this.pending === this.page() && this.el.scrollTop === 0 && this.hasMoreMessagesToLoad()) {
        this.oldScrollHeight = this.el.scrollHeight;
        this.pending = Number(this.page()) + 1;

        this.pushEvent("chat:load-more", {}, (reply, ref) => {
          this.setScrollTop(this.oldScrollHeight)
        })
      }
    })

    this.el.addEventListener("chat:toggle-selection-mode", e => {
      this.pushEvent(`${e.detail.chatType}/toggle-messages-select`, {action: 'off'})
    })
  },

  updated() {
    this.pending = this.page();
  },

  reconnected() {
    this.pending = this.page();
    this.setScrollTop()
  },

  setScrollTop(offset = 0) {
    Promise.all(Array.from(document.images).filter(img => !img.complete).map(img => new Promise(resolve => {
      img.onload = img.onerror = resolve;
    }))).then(() => {
      this.el.scrollTop = this.el.scrollHeight - offset;
    });
  },

  page() {
    return this.el.dataset.page
  },

  hasMoreMessagesToLoad() {
    return this.el.dataset.hasMoreMessages === 'true'
  }
}
