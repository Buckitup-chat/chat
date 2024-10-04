export default class Timestamp extends HTMLElement {
  constructor() {
    super();
  }

  connectedCallback() {
    const date = new Date(this.innerText * 1000);
    const timeString = date.toLocaleTimeString();
    const dateString = date.toLocaleDateString();
    this.textContent = `${timeString} ${dateString}`;
  }
}
