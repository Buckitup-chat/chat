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

    this.handleEvent("chat:select-message", ({id: id, type: chatType}) => {
     const messageBlock = document.querySelector(`#message-block-${id}`);
     const messageBlockCheckbox = messageBlock.querySelector('.selectCheckbox');
  
     if (messageBlockCheckbox.classList.contains('hidden') == true) { return false }
     if (messageBlockCheckbox.classList.contains('checked') == true) { 
       messageBlock.classList.remove('selectedMessageBackground');
       messageBlockCheckbox.classList.remove('checked');
       messageBlockCheckbox.checked = false;
     } else {
       messageBlock.classList.add('selectedMessageBackground');
       messageBlockCheckbox.classList.add('checked');
       messageBlockCheckbox.checked = true;
     }
     if (document.querySelectorAll('.checked').length == 0) {
       this.pushEvent(`${chatType}/toggle-messages-select`, {action: 'off'})
     }
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
