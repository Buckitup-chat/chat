import * as UpChunk from "./upchunk"

let Uploaders = {}
let uploads = {}
let uploadInitializers = {}

const uploadInitializer = (entry, onViewError) => {
  return (chunkCount, status) => {
    let { file, meta: { entrypoint, skip, uuid } } = entry

    chunkCount = (typeof chunkCount == "undefined") ? entry.meta.chunk_count : chunkCount
    status = (typeof status == "undefined") ? entry.meta.status : status

    // Skip uploading duplicate file
    if (skip) {
      return
    }

    let upload = UpChunk.createUpload({ chunkSize: 10240, endpoint: entrypoint, file })
    upload.chunkCount = chunkCount

    if (status == "paused" || status == "pending") {
      upload.pause()
    }

    uploads[uuid] = upload

    // stop uploading in the event of a view error
    onViewError(() => upload.abort())

    // upload error triggers LiveView error
    upload.on("error", (e) => entry.error(e.detail.message))

    let lastProgressUpdate = 0

    // notify progress events to LiveView
    upload.on("progress", (e) => {
      const now = new Date().getTime()

      if (!window.uploaderReorderInProgress && !upload.paused && e.detail < 100 && now - lastProgressUpdate > 1000) {
        entry.progress(e.detail)
        lastProgressUpdate = now
      }
    })

    // success completes the UploadEntry
    upload.on("success", () => entry.progress(100))
  }
}

Uploaders.UpChunk = (entries, onViewError) => {
  entries.forEach(entry => {
    const { meta: { uuid } } = entry
    uploadInitializers[uuid] = uploadInitializer(entry, onViewError)
    uploadInitializers[uuid]()
  })
}

const uploadEventHandlers = {
  "upload:cancel": (e) => {
    uploads[e.detail.uuid].abort()
    delete uploads[e.detail.uuid]
  },
  "upload:pause": (e) => {
    const chunkCount = uploads[e.detail.uuid].chunkCount
    const status = "paused"
    const uuid = e.detail.uuid

    uploads[uuid].abort()
    delete uploads[uuid]

    uploadInitializers[uuid](chunkCount, status)
  },
  "phx:upload:resume": (e) => {
    uploads[e.detail.uuid].resume()
  }
}

export { Uploaders, uploadEventHandlers }
