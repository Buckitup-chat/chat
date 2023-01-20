import { DateTime, Interval } from 'luxon'
import RecortRTC from 'recordrtc'

export default {
  mounted() {
    const wrapper = this.el
    const button = document.getElementById('push-to-talk-button')

    if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
      button.classList.remove('hidden')
    } else {
      return
    }

    const uploaderButton = document.getElementById('uploader-button')
    const form = document.querySelector('#dialog-form,#room-form')
    const ref = wrapper.dataset.ref
    const details = document.getElementById('push-to-talk-details')
    const indicator = document.getElementById('push-to-talk-indicator')
    const status = document.getElementById('push-to-talk-status')
    const duration = document.getElementById('push-to-talk-duration')
    const startIcon = button.querySelector('.start')
    const stopIcon = button.querySelector('.stop')
    let timer
    let startTime

    const startRecording = () => {
      navigator.mediaDevices
        .getUserMedia({ audio: true })
        .then(async (stream) => {
          button.removeEventListener('click', startRecording)

          const recorder = RecortRTC(stream, { type: 'audio' })
          recorder.startRecording()

          const saveAudioMessage = () => {
            button.removeEventListener('click', saveAudioMessage)
            clearInterval(timer)
            button.classList.add('hidden')
            stopIcon.classList.add('hidden')
            startIcon.classList.remove('hidden')
            indicator.classList.add('hidden')
            status.textContent = 'Encoding'
            duration.textContent = ''

            recorder.stopRecording(() => {
              const blob = recorder.getBlob()
              const extension = blob.type.split('/')[1]
              const filename =
                'Audio Recording ' + new Date().toJSON() + '.' + extension
              const recording = new File([blob], filename, {
                lastModified: new Date().getTime(),
                type: blob.type,
              })
              const fileInput = document.getElementById(ref)
              const filesContainer = new DataTransfer()
              filesContainer.items.add(recording)
              fileInput.files = filesContainer.files

              this.uploadTo(fileInput, 'file', fileInput.files)

              button.classList.remove('hidden')
              button.addEventListener('click', startRecording)
              form.classList.remove('hidden')
              details.classList.add('hidden')
              uploaderButton.classList.remove('hidden')
            })
          }

          button.addEventListener('click', saveAudioMessage)

          startIcon.classList.add('hidden')
          stopIcon.classList.remove('hidden')
          details.classList.remove('hidden')
          uploaderButton.classList.add('hidden')
          form.classList.add('hidden')

          startTime = DateTime.now()

          indicator.classList.remove('hidden')
          status.textContent = 'Recording'
          duration.textContent = '00:00'

          timer = setInterval(() => {
            const now = DateTime.now()
            const recordingDuration = Interval.fromDateTimes(
              startTime,
              now
            ).toDuration()
            const format = recordingDuration.hours > 1 ? 'hh:mm:ss' : 'mm:ss'

            duration.textContent = recordingDuration.toFormat(format)
          }, 1000)
        })
    }

    button.addEventListener('click', startRecording)
  },
}
