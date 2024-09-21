import Timestamp from "./webcomponents/timestamp";

export const initWebComponents = () => {
  customElements.define("time-stamp", Timestamp);
}
