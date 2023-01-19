export default {
  mounted() {
    const button = this.el

    if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
      button.classList.remove('hidden')
    } else {
      return
    }

    const startIcon = button.querySelector('.start')
    const stopIcon = button.querySelector('.stop')
    const ref = button.dataset.ref

    const startRecording = () => {
      button.removeEventListener('click', startRecording)

      navigator.mediaDevices
        .getUserMedia({ audio: true, video: false })
        .then((stream) => {
          stopIcon.classList.remove('hidden')
          startIcon.classList.add('hidden')
          let mediaRecorder

          const chunks = []

          try {
            mediaRecorder = new MediaRecorder(stream, {
              mimeType: 'audio/mp4',
            })
          } catch (error) {
            try {
              mediaRecorder = new MediaRecorder(stream, {
                mimeType: 'audio/webm',
              })
            } catch (error) {
              button.classList.add('hidden')
              return
            }
          }

          const extension = mediaRecorder.mimeType.split('/')[1]

          mediaRecorder.addEventListener('dataavailable', (e) => {
            chunks.push(e.data)
          })

          mediaRecorder.addEventListener('stop', () => {
            startIcon.classList.remove('hidden')
            stopIcon.classList.add('hidden')

            const blob = new Blob(chunks, { type: mediaRecorder.mimeType })
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
          })

          const saveAudioMessage = () => {
            button.removeEventListener('click', saveAudioMessage)
            button.addEventListener('click', startRecording)

            mediaRecorder.stop()
          }

          button.addEventListener('click', saveAudioMessage)

          mediaRecorder.start()
        })
    }

    button.addEventListener('click', startRecording)
  },
}
