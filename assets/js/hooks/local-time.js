export const hooks = {
  mounted() {
    this.pushEvent("local-time", {
      locale: Intl.NumberFormat().resolvedOptions().locale,
      timezone: Intl.DateTimeFormat().resolvedOptions().timeZone,
      timezone_offset: -(new Date().getTimezoneOffset() / 60),
      timestamp: Math.floor((new Date()).getTime() / 1000)
    });
    setInterval(() => {
      const time = Math.ceil(Date.now() / 1000);
      this.pushEvent("client-timestamp", {timestamp: time});
    }, 997);
  }
}
