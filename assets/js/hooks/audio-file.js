import Peaks from 'peaks.js'

export default {
  mounted() {
    const overviewContainer = this.el.querySelector('.peaks-overview-container')
    const mediaElement = this.el.querySelector('audio')
    const playButton = this.el.querySelector('button.play .play-circle')
    const pauseButton = this.el.querySelector('button.play .pause-circle')

    const options = {
      overview: {
        container: overviewContainer,
        waveformColor: 'rgba(142, 43, 119, 0.5)',
        playedWaveformColor: 'rgba(142, 43, 119, 1)',
        highlightColor: 'rgba(0, 0, 0, 0.7)',
        playheadColor: 'rgba(142, 43, 119, 1)',
        playheadTextColor: '#aaa',
        showPlayheadTime: false,
        showAxisLabels: false
      },
      mediaElement: mediaElement,
      webAudio: {
        audioContext: new AudioContext()
      },
    }

    Peaks.init(options, (err, _peaks) => {
      if (err) {
        console.error('Failed to initialize Peaks instance: ' + err.message)
        return
      }
    })

    playButton.addEventListener('click', (e) => {
      mediaElement.play()
      e.preventDefault()
    })

    pauseButton.addEventListener('click', (e) => {
      mediaElement.pause()
      e.preventDefault()
    })

    mediaElement.addEventListener('play', () => {
      playButton.classList.add('hidden')
      pauseButton.classList.remove('hidden')
    })

    mediaElement.addEventListener('pause', () => {
      pauseButton.classList.add('hidden')
      playButton.classList.remove('hidden')
    })

    mediaElement.addEventListener('ended', () => {
      const messageBlock = this.el.closest('.messageBlock')
      const parent = messageBlock.parentElement
      const index = [].slice.call(parent.children).indexOf(messageBlock) + 1
      const nextAudioMessage = parent.querySelector(`:nth-child(${index}) ~ .messageBlock[data-type="audio"] [phx-hook="AudioFile"]`)

      if (nextAudioMessage) {
        nextAudioMessage.dispatchEvent(new CustomEvent('chat:play-audio'))
      }
    })

    this.el.addEventListener('chat:play-audio', () => {
      mediaElement.play()
    })
  }
}
