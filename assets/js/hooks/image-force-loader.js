export const hooks = {
  mounted() {
    this.retryDelay = 1000; 
    this.maxRetryDelay = 10000; 

    this.el.addEventListener('error', e => {
      this.reloadImageWithDelay();
      
      this.retryDelay = Math.min(this.retryDelay * 2, this.maxRetryDelay);
    });
  },

  reloadImageWithDelay() {
    setTimeout(() => { this.el.src = this.el.src }, this.retryDelay);
  }
}