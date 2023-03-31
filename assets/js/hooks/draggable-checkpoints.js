import Sortable from 'sortablejs/modular/sortable.core.esm'

export default {
  mounted() {
    const hook = this
    const list = this.el

    new Sortable(list, {
      animation: 150,
      group: 'draggable',
      sort: false,

      onEnd: (e) => {
        if (e.from == e.to)
          return

        hook.pushEventTo(list, 'move_user', {
          pub_key: e.item.getAttribute('phx-value-pub-key'),
          type: e.item.getAttribute('phx-value-type'),
        })
      },
    })
  }
}
