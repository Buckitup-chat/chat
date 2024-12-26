// JS Hook for storing some state in sessionStorage in the browser.
// The server requests stored data and clears it when requested.
export default {
  mounted() {
    this.handleEvent("store", async (obj) => await this.store(obj))
    this.handleEvent("clear", async (obj) => await this.clear(obj))
    this.handleEvent("restore", async (obj) => await this.restore(obj))
    this.handleEvent("store-room", (obj) => this.storeRoom(obj))
    this.handleEvent("reset-rooms-to-backup", (obj) => this.resetRoomsToBackup(obj))
    this.handleEvent("set-legal-notice-accepted", (obj) => this.setLegalNoticeAccepted(obj))
  },

  async store(obj) {
    localStorage.setItem(obj.auth_key, obj.auth_data)
    await BuckitUp.manager.setData(obj.auth_data)
    localStorage.setItem(obj.room_count_key, obj.room_count)
    this.setupAuthEvents(obj.auth_key);
  },

  async restore(obj) {
    const responseData = await this.fullState(obj)
    this.pushEvent(obj.event, responseData)
    if (responseData?.auth) { this.setupAuthEvents(obj.auth_key) }
  },

  async fullState(obj) {
    const authData = localStorage.getItem(obj.auth_key);
    const secureData = await BuckitUp.manager.hasVault() ? await BuckitUp.manager.getData() : null
    const roomCount = localStorage.getItem(obj.room_count_key);
    const legalNoticeAccepted = localStorage.getItem(obj.legal_notice_key)


    const result = (secureData || authData)
      ? {
        auth: (secureData || authData),
        room_count: Number(roomCount),
        legal_notice_accepted: legalNoticeAccepted
      }
      : {}

    return result
  },

  setLegalNoticeAccepted(obj) {
    localStorage.setItem(obj.legal_notice_key, "true")
  },


  async clear(obj) {
    localStorage.removeItem(obj.auth_key);
    localStorage.removeItem(obj.room_count_key);
    await BuckitUp.manager.clearVault();
  },

  storeRoom(obj) {
    var authData = localStorage.getItem(obj.auth_key);
    var dataJson = JSON.parse(authData);
    var roomKeys = dataJson.at(1);

    if (!roomKeys.includes(obj.room_key)) {
      var roomCount = localStorage.getItem(obj.room_count_key);
      var newRoomCount = Number(roomCount) + 1;

      roomKeys.push(obj.room_key)
      localStorage.setItem(obj.auth_key, JSON.stringify(dataJson));
      localStorage.setItem(obj.room_count_key, newRoomCount);
      this.pushEvent(obj.reply, { room_count: newRoomCount, key: obj.room_key })
    }
  },

  resetRoomsToBackup(obj) { localStorage.setItem(obj.key, 0) },

  setupAuthEvents(key) {
    window.addEventListener('storage', event => {
      if (event.key === key && event.newValue === null) {
        location.reload()
      }
    })
  }
}
