import { uint8ToHex } from './crypto.js';

export class VideoSWStreamer {
  constructor({ fileId, encSecret, chunkCount, totalSize, chunkSize, videoElement, baseUrl, onStatus }) {
    this._fileId = fileId;
    this._encSecret = encSecret;
    this._chunkCount = chunkCount;
    this._totalSize = totalSize;
    this._chunkSize = chunkSize || 4_194_304;
    this._video = videoElement;
    this._baseUrl = baseUrl;
    this._onStatus = onStatus || (() => {});
    this._sessionId = null;
  }

  async start() {
    if (!('serviceWorker' in navigator)) {
      this._onStatus('Service Workers not supported', 'error');
      return;
    }

    this._onStatus('Registering service worker...', 'info');
    await navigator.serviceWorker.register('/video-sw.js', { scope: '/' });
    await navigator.serviceWorker.ready;

    if (!navigator.serviceWorker.controller) {
      await new Promise((resolve) => {
        navigator.serviceWorker.addEventListener('controllerchange', resolve, { once: true });
      });
    }

    this._sessionId = crypto.randomUUID();

    navigator.serviceWorker.controller.postMessage({
      type: 'register',
      sessionId: this._sessionId,
      fileId: this._fileId,
      encSecret: uint8ToHex(this._encSecret),
      chunkCount: this._chunkCount,
      totalSize: this._totalSize,
      chunkSize: this._chunkSize,
      baseUrl: this._baseUrl
    });

    this._video.src = `/encrypted-video/${this._sessionId}`;
    this._onStatus('Playing', 'success');
  }

  destroy() {
    if (this._sessionId && navigator.serviceWorker.controller) {
      navigator.serviceWorker.controller.postMessage({
        type: 'unregister',
        sessionId: this._sessionId
      });
    }
    this._video.pause();
    this._video.removeAttribute('src');
    this._video.load();
    this._sessionId = null;
  }
}
