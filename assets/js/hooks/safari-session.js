/**
 * SafariSession Hook
 * 
 * This hook implements a session maintenance mechanism specifically for Safari browsers.
 * It addresses the issue of users getting logged out when a Safari tab is inactive for some time.
 * 
 * Features:
 * - Periodic ping to keep the session alive
 * - Visibility change detection to handle tab switching
 * - Page unload handling to manage session state
 * - Reconnection logic to restore session after connection loss
 */

const SafariSession = {
  // Ping interval in milliseconds (2 minutes)
  PING_INTERVAL: 2 * 60 * 1000,
  
  // Faster ping when tab is not visible (30 seconds)
  BACKGROUND_PING_INTERVAL: 30 * 1000,
  
  mounted() {
    this.pingTimerId = null;
    this.isVisible = !document.hidden;
    
    // Set up visibility change listener
    document.addEventListener("visibilitychange", this.handleVisibilityChange.bind(this));
    
    // Set up beforeunload listener
    window.addEventListener("beforeunload", this.handleBeforeUnload.bind(this));
    
    // Start the ping timer
    this.startPingTimer();
    
    // Handle reconnection
    this.handleSocketReconnection();
  },
  
  destroyed() {
    // Clean up timers and event listeners
    this.clearPingTimer();
    document.removeEventListener("visibilitychange", this.handleVisibilityChange.bind(this));
    window.removeEventListener("beforeunload", this.handleBeforeUnload.bind(this));
  },
  
  handleVisibilityChange() {
    this.isVisible = !document.hidden;
    
    // Restart the ping timer with appropriate interval
    this.clearPingTimer();
    this.startPingTimer();
    
    // When tab becomes visible again, immediately ping to ensure the session is still active
    if (this.isVisible) {
      this.pingServer();
    }
  },
  
  handleBeforeUnload() {
    // Clear timers when page is unloaded
    this.clearPingTimer();
  },
  
  startPingTimer() {
    const interval = this.isVisible ? this.PING_INTERVAL : this.BACKGROUND_PING_INTERVAL;
    this.pingTimerId = setInterval(() => this.pingServer(), interval);
    
    // Send an initial ping
    this.pingServer();
  },
  
  clearPingTimer() {
    if (this.pingTimerId) {
      clearInterval(this.pingTimerId);
      this.pingTimerId = null;
    }
  },
  
  pingServer() {
    if (this.el && this.liveSocket.isConnected()) {
      this.pushEvent("safari_ping", {});
      
      // Also store current timestamp in localStorage as a fallback
      try {
        localStorage.setItem("safari_session_last_ping", Date.now().toString());
      } catch (e) {
        // Ignore storage errors
      }
    }
  },
  
  handleSocketReconnection() {
    // Get the LiveView socket
    const liveSocket = this.liveSocket;
    
    // Store original onOpen function
    const originalOnOpen = liveSocket.socket.onOpen;
    
    // Override onOpen to handle reconnection
    liveSocket.socket.onOpen = () => {
      // Call original onOpen
      originalOnOpen.call(liveSocket.socket);
      
      // After reconnection, immediately ping to maintain the session
      this.pingServer();
    };
  }
};

export default SafariSession;
