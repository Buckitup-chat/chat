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
    this.clearCache()
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
      return this.cacheAuthData(vaultData);
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
      const saved = await BuckitUp.manager.setData(this.enrichAuthData(data))
      if (saved) return;

      return localStorage.setItem(obj.auth_key, data)
    }

    localStorage.setItem(obj.auth_key, data)
  },

  // Enriches the auth data with cached contacts and payload. I.e. contacts and payload not changed on server
  enrichAuthData(data) {
    const list = JSON.parse(data)
    const me = list[0]
    const rooms = list[1]
    const contacts = window?.BuckitUp?.contacts || list[2] || {}
    const payload = window?.BuckitUp?.payload || list[3] || {}
    return JSON.stringify([me, rooms, contacts, payload])
  },

  // Caches the auth data in the window object
  cacheAuthData(data) {
    const list = JSON.parse(data)
    const contacts = list[2] || {}
    const payload = list[3] || {}

    if (!window.BuckitUp) window.BuckitUp = {}
    window.BuckitUp.contacts = contacts
    window.BuckitUp.payload = payload
    
    return data
  },

  // Clears the cached contacts and payload
  clearCache() {
    window.BuckitUp.contacts = {}
    window.BuckitUp.payload = {}
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
