// JS Hook for storing some state in sessionStorage in the browser.
// The server requests stored data and clears it when requested.
export default {
  mounted() {
    this.handleEvent("store", async (obj) => await this.store(obj))
    this.handleEvent("clear", async (obj) => await this.clear(obj))
    this.handleEvent("restore", async (obj) => await this.restore(obj))
    this.handleEvent("store-room", async (obj) => await this.storeRoom(obj))
    this.handleEvent("reset-rooms-to-backup", (obj) => this.resetRoomsToBackup(obj))
    this.handleEvent("set-legal-notice-accepted", (obj) => this.setLegalNoticeAccepted(obj))
  },

  async store(obj) {
    await this.storeAuthData(obj, obj.auth_data)
    localStorage.setItem(obj.room_count_key, obj.room_count)
    this.setupAuthEvents(obj.auth_key);
  },

  async restore(obj) {
    const responseData = await this.fullState(obj)
    this.pushEvent(obj.event, responseData)
    if (responseData?.auth) { this.setupAuthEvents(obj.auth_key) }
  },

  async fullState(obj) {
    const authData = await this.getAuthData(obj)
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


  async clear(obj) {
    localStorage.removeItem(obj.auth_key);
    localStorage.removeItem(obj.room_count_key);
    await BuckitUp.manager.clearVault();
  },

  async storeRoom(obj) {
    var authData = await this.getAuthData(obj);
    var dataJson = JSON.parse(authData);
    var roomKeys = dataJson.at(1);

    if (!roomKeys.includes(obj.room_key)) {
      var roomCount = localStorage.getItem(obj.room_count_key);
      var newRoomCount = Number(roomCount) + 1;

      roomKeys.push(obj.room_key)
      await this.storeAuthData(obj, JSON.stringify(dataJson));
      localStorage.setItem(obj.room_count_key, newRoomCount);
      this.pushEvent(obj.reply, { room_count: newRoomCount, key: obj.room_key })
    }
  },

  async getAuthData(obj) {
    if (await BuckitUp.manager.hasVault()) {
      const vaultData = await BuckitUp.manager.getData()
      return vaultData;
    }

    return localStorage.getItem(obj.auth_key)
  },

  async storeAuthData(obj, data) {
    if (window.location.search == '?local_storage') {
      return localStorage.setItem(obj.auth_key, data)
    }

    const localStoragePresent = !!localStorage.getItem(obj.auth_key)
    const vaultPresent = await BuckitUp.manager.hasVault()
    if (vaultPresent || !localStoragePresent) {
      const saved = await BuckitUp.manager.setData(data)
      if (saved) return;

      return localStorage.setItem(obj.auth_key, data)
    }

    localStorage.setItem(obj.auth_key, data)
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
