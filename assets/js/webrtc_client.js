// WebRTC Client for handling WebRTC signaling
class WebRTCClient {
  constructor() {
    this.socket = null;
    this.channel = null;
    this.peerConnection = null;
    this.roomId = null;
    this.userId = `user-${Math.random().toString(36).substr(2, 9)}`;
    this.peers = new Set();
    this.onSignal = null;
    this.onTrack = null;
    this.onUserJoined = null;
    this.onUserLeft = null;
    this.onConnected = null;
    this.onDisconnected = null;
  }

  // Initialize WebSocket connection and join the room
  connect(roomId, userId = null) {
    if (!roomId) {
      console.error('Room ID is required');
      return;
    }

    this.roomId = roomId;
    this.userId = userId || this.userId;
    
    // Get the WebSocket URL from the current host
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const host = window.location.host;
    const wsUrl = `${protocol}//${host}/webrtc-socket/websocket`;
    
    // Create a new Phoenix Socket
    this.socket = new Phoenix.Socket(wsUrl, {
      params: { user_id: this.userId },
      logger: (kind, msg, data) => { console.log(`[${kind}] ${msg}`, data); }
    });
    
    // Connect to the socket
    this.socket.connect();
    
    // Join the WebRTC channel
    this.channel = this.socket.channel(`room:${roomId}`, { user_id: this.userId });
    
    // Set up channel event handlers
    this.channel.on("signal", this._handleSignal.bind(this));
    this.channel.on("ice_candidate", this._handleICECandidate.bind(this));
    this.channel.on("sdp", this._handleSDP.bind(this));
    this.channel.on("user_joined", this._handleUserJoined.bind(this));
    this.channel.on("user_left", this._handleUserLeft.bind(this));
    
    // Join the channel
    return this.channel.join()
      .receive("ok", resp => { 
        console.log("Joined WebRTC channel successfully", resp);
        if (this.onConnected) this.onConnected(resp);
        return resp;
      })
      .receive("error", resp => { 
        console.error("Unable to join WebRTC channel", resp);
        throw new Error("Failed to join channel");
      });
  }
  
  // Create a new RTCPeerConnection
  createPeerConnection(configuration = {}) {
    const defaults = {
      iceServers: [
        { urls: 'stun:stun.l.google.com:19302' },
        // Add your TURN/STUN servers here if needed stun:buckitup.xyz:3478
      ]
    };
    
    const config = { ...defaults, ...configuration };
    
    this.peerConnection = new RTCPeerConnection(config);
    
    // Set up event handlers
    this.peerConnection.onicecandidate = (event) => {
      if (event.candidate) {
        this.sendICECandidate(event.candidate);
      }
    };
    
    this.peerConnection.ontrack = (event) => {
      if (this.onTrack) {
        this.onTrack(event);
      }
    };
    
    return this.peerConnection;
  }
  
  // Send a signal to a specific peer
  sendSignal(to, data, type = "signal") {
    if (!this.channel) {
      console.error("Not connected to any channel");
      return;
    }
    
    this.channel.push("signal", {
      to: to,
      data: data,
      type: type
    });
  }
  
  // Send ICE candidate to a peer
  sendICECandidate(candidate, to = '*') {
    if (!this.channel) return;
    
    this.channel.push("ice_candidate", {
      to: to,
      candidate: candidate
    });
  }
  
  // Send SDP offer/answer to a peer
  sendSDP(sessionDescription, to = '*') {
    if (!this.channel) return;
    
    this.channel.push("sdp", {
      to: to,
      type: sessionDescription.type,
      sdp: sessionDescription.sdp
    });
  }
  
  // Create and send an offer
  async createOffer(to = '*') {
    if (!this.peerConnection) {
      throw new Error("PeerConnection not initialized");
    }
    
    try {
      const offer = await this.peerConnection.createOffer();
      await this.peerConnection.setLocalDescription(offer);
      this.sendSDP(offer, to);
      return offer;
    } catch (error) {
      console.error("Error creating offer:", error);
      throw error;
    }
  }
  
  // Create and send an answer
  async createAnswer(to = '*') {
    if (!this.peerConnection) {
      throw new Error("PeerConnection not initialized");
    }
    
    try {
      const answer = await this.peerConnection.createAnswer();
      await this.peerConnection.setLocalDescription(answer);
      this.sendSDP(answer, to);
      return answer;
    } catch (error) {
      console.error("Error creating answer:", error);
      throw error;
    }
  }
  
  // Handle incoming signals
  _handleSignal(payload) {
    if (this.onSignal) {
      this.onSignal(payload);
    }
  }
  
  // Handle incoming ICE candidates
  _handleICECandidate(payload) {
    if (!this.peerConnection || payload.from === this.userId) return;
    
    try {
      const candidate = new RTCIceCandidate(payload.candidate);
      this.peerConnection.addIceCandidate(candidate).catch(e => {
        console.error("Error adding ICE candidate:", e);
      });
    } catch (e) {
      console.error("Error creating ICE candidate:", e);
    }
  }
  
  // Handle incoming SDP (offer/answer)
  async _handleSDP(payload) {
    if (!this.peerConnection || payload.from === this.userId) return;
    
    try {
      const desc = new RTCSessionDescription({
        type: payload.type,
        sdp: payload.sdp
      });
      
      await this.peerConnection.setRemoteDescription(desc);
      
      if (payload.type === 'offer') {
        await this.createAnswer(payload.from);
      }
    } catch (error) {
      console.error("Error handling SDP:", error);
    }
  }
  
  // Handle user joined event
  _handleUserJoined(payload) {
    if (payload.user_id !== this.userId) {
      this.peers.add(payload.user_id);
      if (this.onUserJoined) {
        this.onUserJoined(payload.user_id);
      }
    }
  }
  
  // Handle user left event
  _handleUserLeft(payload) {
    this.peers.delete(payload.user_id);
    if (this.onUserLeft) {
      this.onUserLeft(payload.user_id, payload.reason);
    }
  }
  
  // Clean up resources
  disconnect() {
    if (this.peerConnection) {
      this.peerConnection.close();
      this.peerConnection = null;
    }
    
    if (this.channel) {
      this.channel.leave();
      this.channel = null;
    }
    
    if (this.socket) {
      this.socket.disconnect();
      this.socket = null;
    }
    
    this.peers.clear();
  }
}

// Export for use in other modules
if (typeof module !== 'undefined' && module.exports) {
  module.exports = WebRTCClient;
} else {
  window.WebRTCClient = WebRTCClient;
}
