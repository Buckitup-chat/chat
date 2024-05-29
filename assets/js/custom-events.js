export default {
  "chat:clear-value": (e) => {
    e.target.value = ""
  },
  "chat:focus": (e) => {
    const el = e.target;
    setTimeout(() => el.focus(), 100);
  },
  "chat:toggle": (e) => {
    if (e.detail && e.detail.class) {
      e.target.classList.toggle(e.detail.class)
    }
  },
  "chat:set-input-size": (e) => {
    e.target.style.height = '';
    e.target.style.height = (e.target.scrollHeight > 150 ? 150 : e.target.scrollHeight) + 'px';
  },
  "chat:set-dropdown-position": (e) => {
    const relativeElementRect = document.getElementById(e.detail.relativeElementId).getBoundingClientRect();

    if (relativeElementRect.bottom + 200 > window.innerHeight && relativeElementRect.top > 200) {
      e.target.style.bottom = 0;
      e.target.style.top = '';
    } else {
      e.target.style.top = 28 + 'px';
      e.target.style.bottom = '';
    }

    if (relativeElementRect.width < e.target.offsetWidth) {
      e.target.style.left = 0
    }
  },
  "chat:select-message": (e) => {
    const messageBlock = e.target;
    const messageBlockCheckbox = messageBlock.querySelector('.selectCheckbox');
    messageBlock.classList.toggle('selectedMessageBackground');
    messageBlockCheckbox.classList.toggle('checked');
    messageBlockCheckbox.checked = !messageBlockCheckbox.checked;

    setTimeout(() => {
      if (document.querySelector("#chat-messages").classList.contains('selectMode') == false) {
        return false
      }

      const allCheckboxes = document.querySelectorAll('.checked')

      if (allCheckboxes.length == 0) {
        document.getElementById("chatContent").dispatchEvent(
          new CustomEvent('chat:toggle-selection-mode', { detail: { chatType: e.detail.chatType } })
        )
      }
      const deleteButton = document.getElementById("delete-btn");
      const icon = document.querySelector('.x-icon');
      const deleteSpan = document.getElementById('delete-span');
      if (Array.from(allCheckboxes).some(el => el.previousElementSibling.classList.contains('x-peer'))) {
        icon.classList.add('fill-gray-300')
        deleteButton.disabled = true;
        deleteSpan.classList.add('text-gray-300')
      } else {
        deleteSpan.classList.remove('text-gray-300')
        icon.classList.remove('fill-gray-300')
        deleteButton.disabled = false;
      }

    }, 200);
  },
  "chat:messages-to-delete": (e) => {
    setTimeout(() => {
      const checkboxes = document.querySelectorAll('.selectCheckbox.checked');
      const deleteButton = e.target.querySelector('.deleteMessageButton');
      const messages = []
      for (const checkbox of checkboxes) {
        const message = checkbox.parentNode;
        if (message.getAttribute('phx-value-is-mine') == 'true' && message.classList.contains('hidden') == false) {
          messages.push({
            id: message.getAttribute('phx-value-id'),
            index: message.getAttribute('phx-value-index')
          });
        }
      }
      deleteButton.setAttribute('phx-value-messages', JSON.stringify(messages));
    }, 200);
  },
  "phx:chat:scroll": (e) => {
    setTimeout(() => {
      document.querySelector(e.detail.to).scrollIntoView(
        { behavior: "smooth", block: "center", inline: "nearest" }
      );
    }, 900)
  },
  "phx:chat:toggle": (e) => {
    if (e.detail && e.detail.class && e.detail.to) {
      document
        .querySelector(e.detail.to)
        .classList.toggle(e.detail.class)
    }
  },
  "phx:chat:redirect": (e) => {
    const openUrl = (url) => window.location = url;
    url = e.detail.url
    url && openUrl(url)
  },
  "phx:chat:focus": (e) => {
    const el = document.querySelector(e.detail.to);
    setTimeout(() => el.focus(), 100);
  },
  "phx:chat:change": (e) => {
    const el = document.querySelector(e.detail.to);
    el.innerHTML = e.detail.content;
  },
  "phx:chat:bulk-change": (e) => {
    const elements = document.querySelectorAll(e.detail.to);
    elements.forEach((el) => {
      el.innerHTML = e.detail.content;
    });
  },
  "phx:scroll-to-bottom": (e) => {
    setTimeout(() => {
      const chatContent = document.querySelector('.a-content-block');
      chatContent.scrollTo({ top: chatContent.scrollHeight })
    }, 0)
  },
  "phx:scroll-uploads-to-top": (e) => {
    const uploader = document.querySelector('.a-uploader');
    const mobileUploader = document.querySelector('.a-mobile-uploader');
    uploader.scrollTop = -uploader.scrollHeight;
    mobileUploader.scrollTop = -mobileUploader.scrollHeight;
  },
  "phx:gallery:preload": (e) => {
    const img = new Image();
    img.onload = function () {
      const preloadedList = document.getElementById(e.detail.to);
      preloadedList.appendChild(img);
      setTimeout(() => {
        img.remove()
      }, '30000');
    }
    img.classList.add('hidden')
    img.src = e.detail.url;
  },
  "phx:js-event": (e) => {
    liveSocket.execJS(document.documentElement, e.detail.data)
  },
  "phx:copy": (e) => {
    navigator.clipboard.writeText(e.target.value)
  },
  "phx:js-exec": ({ detail }) => {
    document.querySelectorAll(detail.to).forEach(el => {
      liveSocket.execJS(el, el.getAttribute(detail.attr))
    })
  },
}
