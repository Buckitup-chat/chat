import QRCode from 'qrcode';
import { utils } from 'ethers';
import * as $enigma from './enigma';
import QrScanner from 'qr-scanner';

export default class QRHandshakeManager extends EventTarget {
	constructor(container, account, options) {
		console.log('QRHandshakeManager', account);
		super();
		this.account = account;
		this.container = container;
		this.options = options;
		this.scanning = false;
		this.state = {
			challenge: null,
			signature: null,
			verified: 0,
			completed: false,
			contactChallenge: null,
			contactAddress: null,
			contactPublicKey: null,
			contactName: null,
			contactVerified: 0,
		};

		this.staticString = 'BKP';
		this.qrCode = null;
		this.qrScanner = null;
		this.init();
	}

	async init() {
		this.container.innerHTML = this.getTemplate();
		this.qrCodeWrapper = this.container.querySelector('._qrh_wrapper');
		this.qrCode = this.container.querySelector('#qrCode');
		this.qrScanner = new QrScanner(this.container.querySelector('#qrScanner'), (result) => this.readQr(result.data), {
			returnDetailedScanResult: true,
			preferredCamera: 'user',
			highlightScanRegion: true,
			highlightCodeOutline: true,
			calculateScanRegion: (video) => {
				const width = video.videoWidth;
				const height = video.videoHeight;
				const scanSize = 0.95; // 100% of video size
				return {
					x: (width * (1 - scanSize)) / 2, // Center horizontally
					y: (height * (1 - scanSize)) / 2, // Center vertically
					width: width * scanSize, // 80% width
					height: height * scanSize, // 80% height
				};
			},
		});
	}

	getTemplate() {
		return `
        <div class="_qrh">
			<div class="_qrh_wrapper" id="qrCodeWrapper" >
				<div class="_qrh_container">
					<canvas id="qrCode"></canvas>
				</div>
			</div>
			<div class="_qrh_scanner" id="qrScannerWrap">
				<video id="qrScanner"></video>
			</div>
        </div>
      	`; //
	}
	emitEvent(eventName, detail = {}) {
		this.dispatchEvent(new CustomEvent(eventName, { detail }));
	}

	generateChallenge() {
		const staticBytes = utils.toUtf8Bytes(this.staticString); // Convert 'buckitup' to bytes
		const randomBytes = utils.randomBytes(10); // Generate 16 random bytes
		this.state.challenge = utils.base58.encode(Buffer.concat([staticBytes, randomBytes])); // .toString('base58')
	}

	async updateQr() {
		if (this.qrCode && this.state.challenge) {
			let color = this.options.scanningColor;
			if (this.state.contactChallenge && !this.state.signature) {
				this.state.signature = $enigma.signChallenge(this.state.contactChallenge + this.account.name, this.account.privateKeyB64);
				if ('vibrate' in navigator) navigator.vibrate([50]);
			}

			const displayName = this.state.signature ? utils.base58.encode(new TextEncoder().encode(this.account.name)) : '';

			const msg = `${this.state.verified}${this.state.challenge}${this.state.signature || ''}${displayName}`;
			console.log('msg1', msg, this.state.verified, this.state.challenge, this.state.signature, this.account.name, displayName);

			if (this.state.signature) color = this.options.detectedColor;
			if (this.state.verified && this.state.contactVerified) color = this.options.verifiedColor;

			QRCode.toCanvas(this.qrCode, msg, {
				errorCorrectionLevel: 'M',
				height: 360,
				width: 360,
				quality: 1,
				margin: 0,
				color: { dark: color },
			});

			if (this.state.verified && this.state.contactVerified && !this.state.completed) {
				this.state.completed = true;
				this.qrScanner.stop();

				this.emitEvent('handshakeCompleted', {
					address: this.state.contactAddress,
					publicKey: this.state.contactPublicKey,
					name: this.state.contactName,
				});

				if ('vibrate' in navigator) navigator.vibrate([500, 100, 500, 100, 500]);

				//await this.wait(3000);
				this.scanning = false;
				//this.container.querySelector('#qrCodeWrapper').style.display = 'none';
				this.emitEvent('scanning', this.scanning);
			}
		}
	}

	stopScan() {
		if (this.qrScanner) {
			this.qrScanner.stop();
			this.scanning = false;
			this.container.querySelector('#qrCodeWrapper').style.display = 'none';
		}
	}

	async toggleScanner() {
		try {
			if (this.scanning && this.qrScanner) {
				this.qrScanner.stop();
				//this.dispose();
				this.scanning = false;
				this.container.querySelector('#qrCodeWrapper').style.display = 'none';
				this.emitEvent('scanning', this.scanning);
				this.updateQr();
				return;
			}
			this.reset();
			this.scanning = true;
			this.emitEvent('scanning', this.scanning);
			await this.wait(100);
			await this.qrScanner.start();

			await this.showCountdown(3);

			this.generateChallenge();
			this.container.querySelector('#qrCodeWrapper').style.height = 'unset';
			//this.container.querySelector('#qrScannerWrap').style.opacity = 0;

			this.updateQr();
		} catch (error) {
			console.error('Init Scanning error:', error);
		}
	}

	async showCountdown(seconds) {
		for (let i = seconds; i > 0; i--) {
			this.emitEvent('handshakeCountdown', i); // 👈 Send countdown value to UI
			console.log(i); // ✅ Log countdown in console
			await new Promise((resolve) => setTimeout(resolve, 1000)); // ⏳ Wait 1 second
		}
		this.emitEvent('handshakeCountdown', 0); // 🚀 Notify UI to start
	}

	readQr(msg) {
		try {
			// Extract the fixed parts based on known lengths
			const verified = parseInt(msg[0]); // First character (1 char)
			const challenge = msg.slice(1, 19); // Next 18 characters (2nd to 19th char)
			const signature = msg.length > 19 ? msg.slice(19, 107) : null; // 19th to 107th char (if present)
			const displayNameEnc = msg.length > 107 ? msg.slice(107) : null;

			console.log('msg', { length: msg.length, msg, verified, challenge, signature, displayNameEnc });

			if (challenge) {
				const decodedChallengeBytes = utils.base58.decode(challenge);
				const contactChallengeDec = new TextDecoder().decode(decodedChallengeBytes);

				if (challenge && contactChallengeDec.startsWith(this.staticString)) {
					if (this.state.contactChallenge !== challenge) {
						if (this.state.contactChallenge) {
							this.reset();
						}
						this.state.contactChallenge = challenge;
					}

					if (signature) {
						const decodedNameBytes = utils.base58.decode(displayNameEnc);
						const displayName = new TextDecoder().decode(decodedNameBytes);

						const publicKeyCompact = $enigma.recoverPublicKey(this.state.challenge + displayName, signature);
						const publicKey = utils.computePublicKey('0x' + $enigma.convertPublicKeyToHex(publicKeyCompact));

						this.state.contactAddress = utils.computeAddress(publicKey);
						this.state.contactPublicKey = publicKeyCompact;
						this.state.contactName = displayName;
						this.state.verified = 1;
						this.state.contactVerified = verified;
					}
					this.updateQr();
				}
			}
		} catch (error) {
			console.error('Init Scanning error:', error);
		}
	}

	dispose() {
		try {
			this.qrScanner.dispose();
		} catch (error) {
			//console.log(error);
		}
	}

	reset() {
		this.state.verified = 0;
		this.state.completed = 0;
		this.state.signature = null;
		this.state.contactChallenge = null;
		this.state.contactAddress = null;
		this.state.contactPublicKey = null;
		this.state.contactName = null;
		this.state.contactVerified = 0;
	}

	wait(delay = 500) {
		return new Promise((resolve) =>
			setTimeout(() => {
				resolve();
			}, delay),
		);
	}
}
