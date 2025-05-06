// We import the CSS which is extracted to its own file by esbuild.
// Remove this line if you add a your own CSS build pipeline (e.g postcss).

// If you want to use Phoenix channels, run `mix help phx.gen.channel`
// to get started and then uncomment the line below.
// import "./user_socket.js"

// You can include dependencies in two ways.
//
// The simplest option is to put them in assets/vendor and
// import them using relative paths:
//
//     import "../vendor/some-package.js"
//
// Alternatively, you can `npm install some-package --prefix assets` and import
// them using a path starting with the package name:
//
//     import "some-package"
//

import topbar from "topbar" // instead of ../vendor/topbar
import { getHooks } from "live_vue"
import liveVueApp from "../vue"
// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { UpChunkUploader, uploadEventHandlers } from "./upchunk_upload"
// import topbar from "../vendor/topbar"
import Hooks from "./hooks"
import CustomEvents from "./custom-events"
import { initWebComponents } from "./web-components"
import { EncryptionManager } from "./EncryptionManager";
import { Enigma } from "./Enigma";

import "../css/app.css"

window.BuckitUp = {
  manager: new EncryptionManager(),
  enigma: new Enigma(),
  tools: {
    setVaultId: id => {
      const req = indexedDB.open('keyval-store', 1);
      req.onupgradeneeded = e => {
        // Create object store without keyPath for out-of-line keys
        e.target.result.createObjectStore('keyval');
      };
      req.onsuccess = e => {
        const db = e.target.result;
        const tx = db.transaction('keyval', 'readwrite');
        const store = tx.objectStore('keyval');
        // Use the key as first parameter and value as second parameter for out-of-line keys
        const request = store.put(id, 'vault-id');
        
        request.onsuccess = () => console.log('✅ vault-id set to', id);
        request.onerror = () => console.error('Failed to set vault-id:', request.error);
        
        tx.oncomplete = () => console.log('✅ Transaction completed successfully');
        tx.onerror = () => console.error('Transaction error:', tx.error);
      };
      req.onerror = () => console.error('Database error:', req.error);
    },
    
    /**
     * Gets known users from vaults registry and adds them to BuckitUp.contacts
     * @returns {Promise<void>}
     */
    getContactsFromVaultsRegistry: async function() {
      try {
        // Get vaults registry from local storage
        const vaultsRegistry = await window.BuckitUp.manager.getVaultsRegistry();
        
        if (!vaultsRegistry || !Array.isArray(vaultsRegistry) || vaultsRegistry.length === 0) {
          console.log('No vaults registry found or empty registry');
          return;
        }
        
        console.log(`Found ${vaultsRegistry.length} entries in vaults registry`);
        
        // Find current vault to identify current user
        const currentVault = vaultsRegistry.find(vault => vault.current === true);
        if (!currentVault) {
          console.log('No current vault found in registry');
          return;
        }
        
        // Initialize contacts if not present
        if (!window.BuckitUp.contacts) {
          window.BuckitUp.contacts = {};
        }
        
        // Add each vault entry to contacts if not already present
        vaultsRegistry.forEach(vault => {
          // Skip current user's vault
          if (vault.vaultId === currentVault.vaultId) {
            return;
          }
          
          if (vault.publicKey && vault.name) {
            // Remove 0x prefix if present
            const publicKey = vault.publicKey.startsWith('0x') ? 
              vault.publicKey.substring(2) : vault.publicKey;
            
            // Add to contacts if not already present
            if (!window.BuckitUp.contacts[publicKey]) {
              window.BuckitUp.contacts[publicKey] = {
                "name": vault.name,
                "address": vault.address || ""
              };
              console.log(`Added contact: ${vault.name}`);
            }
          }
        });
        
        console.log(`Updated BuckitUp.contacts with ${Object.keys(window.BuckitUp.contacts).length} entries`);
      } catch (error) {
        console.error('Error adding contacts from vaults registry:', error);
      }
    }
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: {
    _csrf_token: csrfToken,
    tz_info: Hooks.LocalTime.info(),
    storage: await Hooks.LocalStateStore.fullState({
      auth_key: "buckitUp-chat-auth-v2",
      room_count_key: "buckitUp-room-count-v2",
      legal_notice_key: "agreementAccepted"
    })
  },
  hooks: {
    ...Hooks,
    ...getHooks(liveVueApp)
  },
  uploaders: { UpChunkUploader }
})

const listeners = {
  ...CustomEvents,
  ...uploadEventHandlers
};
Object.keys(listeners).forEach(key => {
  window.addEventListener(key, listeners[key]);
})

// Show progress bar on live navigation and form submits
topbar.config({ barColors: { 0: "#29d" }, shadowColor: "rgba(0, 0, 0, .3)" })
let topBarScheduled = undefined;
window.addEventListener("phx:page-loading-start", () => {
  if (!topBarScheduled) {
    topBarScheduled = setTimeout(() => topbar.show(), 120);
  }
  ;
});
window.addEventListener("phx:page-loading-stop", () => {
  clearTimeout(topBarScheduled);
  topBarScheduled = undefined;
  topbar.hide();
});

// back button fix
window.addEventListener("popstate", _e => {
  history.pushState(null, null, window.location.pathname);

  const target = document.querySelector('.x-back-target')
  target && target.click()
}, false);
history.pushState({}, null, null);

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

initWebComponents();
