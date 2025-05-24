export default class Timestamp extends HTMLElement {
  constructor() {
    super();
  }

  // Define which attributes should be observed for changes
  static get observedAttributes() {
    return ['data-unixtime'];
  }

  // Called when the element is added to the DOM
  connectedCallback() {
    this.updateTimestamp();
  }

  // Called when an observed attribute changes
  attributeChangedCallback(name, oldValue, newValue) {
    if (name === 'data-unixtime' && oldValue !== newValue) {
      this.updateTimestamp();
    }
  }

  // Unified method to update the timestamp display
  updateTimestamp() {
    if (!this.dataset.unixtime) return;
    
    const date = new Date(this.dataset.unixtime * 1000);
    const timeString = date.toLocaleTimeString();
    const dateString = date.toLocaleDateString();
    this.textContent = `${timeString} ${dateString}`;
  }
}
