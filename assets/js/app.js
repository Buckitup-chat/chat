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

// Include phoenix_html to handle method=PUT/DELETE in forms and buttons.
import "phoenix_html"
// Establish Phoenix Socket and LiveView configuration.
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import topbar from "../vendor/topbar"
import * as LocalStateStore from "./hooks/local-storage"
import * as LocalTime from "./hooks/local-time"
import * as Chat from "./hooks/chat"



let Hooks = {}

Hooks.LocalStateStore = LocalStateStore.hooks
Hooks.LocalTime = LocalTime.hooks
Hooks.Chat = Chat.hooks

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
      params: {_csrf_token: csrfToken},
      hooks: Hooks
})

const listeners = {
  "chat:clear-value": (e) => {e.target.value = ""},
  "chat:focus": (e) => {const el = e.target; setTimeout(() => el.focus(), 100);},
  "chat:toggle": (e) => {
    if (e.detail && e.detail.class) {
      e.target.classList.toggle(e.detail.class)
    }
  },
  "chat:set-input-size": (e) => {
    e.target.style.height = '';
    e.target.style.height = (e.target.scrollHeight > 150 ? 150 : e.target.scrollHeight) + 'px';
  },
  "chat:set-dropdown-position": (e) => {
    const relativeElementRect = document.getElementById(e.detail.relativeElementId).getBoundingClientRect();
    
    if (relativeElementRect.bottom + 200 > window.innerHeight && relativeElementRect.top > 200) {
      e.target.style.bottom = 0;
    } else {
      e.target.style.top = 28 + 'px';
    } 
    
    if (relativeElementRect.width < e.target.offsetWidth) { e.target.style.left = 0 }
  },
  "chat:select-message": (e) => {
    setTimeout(() => {
      if (document.querySelector("#chat-messages").classList.contains('selectMode') == false) { return false }
      
      const messageBlock = e.target;
      const messageBlockCheckbox = messageBlock.querySelector('.selectCheckbox');
      messageBlock.classList.toggle('selectedMessageBackground');
      messageBlockCheckbox.classList.toggle('checked');
      messageBlockCheckbox.checked = !messageBlockCheckbox.checked;
      if (document.querySelectorAll('.checked').length == 0) {  
        document.getElementById("chatContent").dispatchEvent(
          new CustomEvent('chat:toggle-selection-mode', {detail: {chatType: e.detail.chatType}})
        )
      }
  }, 200);
  },
  "chat:messages-to-delete": (e) => {
    setTimeout(() => {
      const checkboxes = document.querySelectorAll('.selectCheckbox.checked');
      const deleteButton = e.target.querySelector('.deleteMessageButton');
      const messages = []
      for (const checkbox of checkboxes) {
        const message = checkbox.parentNode;
        if (message.getAttribute('phx-value-is-mine') == 'true' && message.classList.contains('hidden') == false) {
          messages.push({
            id: message.getAttribute('phx-value-id'),
            timestamp: message.getAttribute('phx-value-timestamp')
          });
        }
      }
      deleteButton.setAttribute('phx-value-messages', JSON.stringify(messages));
    }, 200);
   },
  "phx:chat:toggle": (e) => {
    if (e.detail && e.detail.class && e.detail.to) {
      document
        .querySelector(e.detail.to)
        .classList.toggle(e.detail.class)
    }
  },
  "phx:chat:redirect": (e) => { 
    const openUrl = (url) => window.location = url;
    url = e.detail.url
    url && openUrl(url)
  },  
  "phx:chat:focus": (e) => {const el = document.querySelector(e.detail.to); setTimeout(() => el.focus(), 100);},
  "phx:chat:change": (e) => {const el = document.querySelector(e.detail.to); el.innerHTML = e.detail.content;},
};
for (key in listeners) {
  window.addEventListener(key, listeners[key]);
}

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", info => topbar.show())
window.addEventListener("phx:page-loading-stop", info => topbar.hide())

// back button fix 
window.addEventListener("popstate", e => {
  history.pushState(null, null, window.location.pathname);

  const target = document.querySelector('.x-back-target')
  if (target) {
    target.click()
  }
}, false);
history.pushState({}, null, null);

// connect if there are any LiveViews on the page
liveSocket.connect()

// expose liveSocket on window for web console debug logs and latency simulation:
// >> liveSocket.enableDebug()
// >> liveSocket.enableLatencySim(1000)  // enabled for duration of browser session
// >> liveSocket.disableLatencySim()
window.liveSocket = liveSocket

