import { uint8ToHex } from './crypto.js';

export class VideoSWStreamer {
  constructor({ fileId, encSecret, chunkCount, totalSize, chunkSize, videoElement, baseUrl, onStatus, getAuthToken }) {
    this._fileId = fileId;
    this._encSecret = encSecret;
    this._chunkCount = chunkCount;
    this._totalSize = totalSize;
    this._chunkSize = chunkSize || 4_194_304;
    this._video = videoElement;
    this._baseUrl = baseUrl;
    this._onStatus = onStatus || (() => {});
    this._getAuthToken = getAuthToken || (() => Promise.resolve(null));
    this._sessionId = null;
    this._swMessageHandler = null;
  }

  async start() {
    if (!('serviceWorker' in navigator)) {
      this._onStatus('Service Workers not supported', 'error');
      return;
    }

    this._onStatus('Registering service worker...', 'info');

    const controllerReady = navigator.serviceWorker.controller
      ? Promise.resolve()
      : new Promise((resolve) => {
          navigator.serviceWorker.addEventListener('controllerchange', resolve, { once: true });
        });

    await navigator.serviceWorker.register('/video-sw.js', { scope: '/' });
    await navigator.serviceWorker.ready;
    await controllerReady;

    this._sessionId = crypto.randomUUID();

    const authToken = await this._getAuthToken('file_chunk').catch(() => null);

    this._swMessageHandler = (e) => {
      if (e.data?.type === 'auth_needed' && e.data.sessionId === this._sessionId) {
        this._getAuthToken('file_chunk')
          .then((token) => {
            navigator.serviceWorker.controller?.postMessage({
              type: 'auth_token',
              sessionId: this._sessionId,
              token
            });
          })
          .catch(() => {});
      }
    };
    navigator.serviceWorker.addEventListener('message', this._swMessageHandler);

    navigator.serviceWorker.controller.postMessage({
      type: 'register',
      sessionId: this._sessionId,
      fileId: this._fileId,
      encSecret: uint8ToHex(this._encSecret),
      chunkCount: this._chunkCount,
      totalSize: this._totalSize,
      chunkSize: this._chunkSize,
      baseUrl: this._baseUrl,
      authToken
    });

    this._video.src = `/encrypted-video/${this._sessionId}`;
    this._onStatus('Playing', 'success');
  }

  destroy() {
    if (this._swMessageHandler) {
      navigator.serviceWorker.removeEventListener('message', this._swMessageHandler);
      this._swMessageHandler = null;
    }
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
