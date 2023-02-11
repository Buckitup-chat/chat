import Sortable from 'sortablejs/modular/sortable.core.esm'

export default {
  mounted() {
    const hook = this
    const list = this.el

    new Sortable(list, {
      handle: '.sorting-handle',
      onClone: (e) => {
        list.classList.add('bg-gray-300')
        window.uploaderReorderInProgress = true
        e.clone.id = ''
      },
      onEnd: (e) => {
        hook.pushEvent('upload:move', {
          index: e.newIndex,
          uuid: e.item.dataset.uuid,
        }, () => {
          list.classList.remove('bg-gray-300')
          window.uploaderReorderInProgress = false
        })
      },
    })
  },
}
