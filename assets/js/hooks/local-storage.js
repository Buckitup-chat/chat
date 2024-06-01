// JS Hook for storing some state in sessionStorage in the browser.
// The server requests stored data and clears it when requested.
export default {
  mounted() {
    this.handleEvent("store", (obj) => this.store(obj))
    this.handleEvent("clear", (obj) => this.clear(obj))
    this.handleEvent("restore", (obj) => this.restore(obj))
    this.handleEvent("store-room", (obj) => this.storeRoom(obj))
    this.handleEvent("reset-rooms-to-backup", (obj) => this.resetRoomsToBackup(obj))
    this.handleEvent("set-legal-notice-accepted", (obj) => this.setLegalNoticeAccepted(obj))
  },

  store(obj) {
    localStorage.setItem(obj.auth_key, obj.auth_data)
    localStorage.setItem(obj.room_count_key, obj.room_count)
    this.setupAuthEvents(obj.auth_key);
  },

  restore(obj) {
    const responseData = this.fullState(obj)
    this.pushEvent(obj.event, responseData)
    if (responseData?.auth) { this.setupAuthEvents(obj.auth_key) }
  },

  fullState(obj) {
    const authData = localStorage.getItem(obj.auth_key);
    const roomCount = localStorage.getItem(obj.room_count_key);
    const legalNoticeAccepted = localStorage.getItem(obj.legal_notice_key)

    return authData
      ? {
        auth: authData,
        room_count: Number(roomCount),
        legal_notice_accepted: legalNoticeAccepted
      }
      : {}
  },

  setLegalNoticeAccepted(obj) {
    localStorage.setItem(obj.legal_notice_key, "true")
  },


  clear(obj) {
    localStorage.removeItem(obj.auth_key);
    localStorage.removeItem(obj.room_count_key);
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
