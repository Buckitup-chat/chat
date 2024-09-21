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
import { Socket } from "phoenix"
import { LiveSocket } from "phoenix_live_view"
import { UpChunkUploader, uploadEventHandlers } from "./upchunk_upload"
import topbar from "../vendor/topbar"
import Hooks from "./hooks"
import CustomEvents from "./custom-events"
import { initWebComponents } from "./web-components"

let csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  params: {
    _csrf_token: csrfToken,
    tz_info: Hooks.LocalTime.info(),
    storage: Hooks.LocalStateStore.fullState({
      auth_key: "buckitUp-chat-auth-v2",
      room_count_key: "buckitUp-room-count-v2",
      legal_notice_key: "agreementAccepted"
    })
  },
  hooks: Hooks,
  uploaders: { UpChunkUploader }
})

const listeners = {
  ...CustomEvents,
  ...uploadEventHandlers
};
for (key in listeners) {
  window.addEventListener(key, listeners[key]);
}

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

const WebAuthN = async () => {
  const createCreds = async () => {
    const randomStringFromServer = "12345678901234567890123456789012";
    const publicKeyCredentialCreationOptions = {
      challenge: Uint8Array.from(
        randomStringFromServer, c => c.charCodeAt(0)),
      rp: {
        name: "BuckitUp",
        id: "localhost",
      },
      user: {
        id: Uint8Array.from(
          "UZSL85T9AFC", c => c.charCodeAt(0)),
        name: "large Blob support check testname",
        displayName: "Login",
      },
      pubKeyCredParams: [{ alg: -7, type: "public-key" }, { alg: -257, type: "public-key" }],
      authenticatorSelection: {
        authenticatorAttachment: "platform",
      },
      timeout: 60000,
      attestation: "direct",
      extensions: {
        largeBlob: {
          support: "preferred",//"preferred",  // Or "required".
        },
        prf: {
          support: "preferred"
        }
      },
    };

    const credential = await navigator.credentials.create({
      publicKey: publicKeyCredentialCreationOptions
    });

    const extSupport = credential.getClientExtensionResults();
    console.log("hi", credential, extSupport)

    if (extSupport.largeBlob.supported) {
      alert("large blob support");
    } else {
      alert("no support :(")
    }
  };

  return await createCreds();
};
// WebAuthN();
