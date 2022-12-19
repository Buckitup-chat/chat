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

    this.el.addEventListener("chat:download-messages", e => {
      const checkboxes = document.querySelectorAll(".selectCheckbox.checked");
      const messages = [];

      let timeout = 0;

      for (const checkbox of checkboxes) {
        const message = checkbox.parentNode;

        if (message.classList.contains("hidden") == false) {
          messages.push({
            id: message.getAttribute("phx-value-id"),
            index: message.getAttribute("phx-value-index")
          });
        }

        setTimeout(() => message.click(), timeout);
        timeout += 200;
      }

      this.pushEvent(`${e.detail.chatType}/download-messages`, { messages: JSON.stringify(messages) })
    })

    this.el.addEventListener("chat:toggle-selection-mode", e => {
      this.pushEvent(`${e.detail.chatType}/toggle-messages-select`, { action: 'off' })
    })

    this.handleEvent("chat:scroll-down", e => { setTimeout(() => { this.setScrollTop() }, 300) })
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
