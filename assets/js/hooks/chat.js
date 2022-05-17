export const hooks = {
  mounted() {
    this.scrollToBottom();
    this.pending = this.page();

    this.el.addEventListener("scroll", e => {
      if (this.pending === this.page() && this.el.scrollTop === 0 && this.hasMoreMessagesToLoad()){        
        this.pending = Number(this.page()) + 1;
        this.oldScrollHeight = this.el.scrollHeight;
        
        this.pushEvent("chat:load-more", {foo: "bar"}, (reply, ref) => {
          Promise.all(Array.from(document.images).filter(img => !img.complete).map(img => new Promise(resolve => { img.onload = img.onerror = resolve; }))).then(() => {
            this.el.scrollTop = this.el.scrollHeight - this.oldScrollHeight;
          });
          })
      }
    })
  },

  updated() {
    this.scrollToBottom()
    this.pending = this.page();
  },

  reconnected(){
    this.scrollToBottom()
    this.pending = this.page();
  },
  
  scrollToBottom() {
    Promise.all(Array.from(document.images).filter(img => !img.complete).map(img => new Promise(resolve => { img.onload = img.onerror = resolve; }))).then(() => {
      console.log(this.el.scrollHeight)
      this.el.scroll({top: this.el.scrollHeight, behavior: 'smooth'});
    });
  },

  page() { return this.el.dataset.page},

  hasMoreMessagesToLoad() { return this.el.dataset.hasMoreMessages === 'true' }
}
