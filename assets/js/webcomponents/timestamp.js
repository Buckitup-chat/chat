export default class Timestamp extends HTMLElement {
  constructor() {
    super();
  }

  connectedCallback() {
    const date = new Date(this.dataset.unixtime * 1000);
    const timeString = date.toLocaleTimeString();
    const dateString = date.toLocaleDateString();
    this.textContent = `${timeString} ${dateString}`;
  }
}
