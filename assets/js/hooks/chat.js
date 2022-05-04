export const hooks = {
  mounted() {
    console.log(this.el);
    this.el.scroll({ top: 1000, behavior: 'auto' });    
  }
}
