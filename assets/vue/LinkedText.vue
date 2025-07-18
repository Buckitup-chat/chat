<!--
  LinkedText component
  - Takes text content and converts URLs to clickable links
  - Preserves existing <a> tags in the input
  - All links have target="_blank" to open in new tab
  - Supports custom styling through class props
-->

<template>
  <span :class="className" ref="contentContainer">
    <slot></slot>
  </span>
</template>

<script>
export default {
  name: 'LinkedText',
  props: {
    className: {
      type: String,
      default: ''
    }
  },
  mounted() {
    // Process the slot content after component is mounted
    this.processContent();
  },
  updated() {
    // Re-process content when component is updated
    this.processContent();
  },
  methods: {
    processContent() {
      if (!this.$refs.contentContainer) return;
      
      // Process all text nodes in the DOM, ignoring text inside <a> tags
      this.processTextNodes(this.$refs.contentContainer);
    },
    
    processTextNodes(node) {
      // If this is a text node, process it
      if (node.nodeType === Node.TEXT_NODE) {
        const newContent = this.linkifyText(node.textContent);
        if (newContent !== node.textContent) {
          const newNode = document.createElement('span');
          newNode.innerHTML = newContent;
          node.parentNode.replaceChild(newNode, node);
          return;
        }
      }
      
      // If it's an element node, check if it's an <a> tag
      if (node.nodeType === Node.ELEMENT_NODE) {
        // Skip processing inside <a> tags
        if (node.nodeName.toLowerCase() === 'a') {
          return;
        }
        
        // Process child nodes recursively
        // We need to create a copy of childNodes because it's a live collection
        // that would change as we replace nodes
        const children = Array.from(node.childNodes);
        children.forEach(child => {
          this.processTextNodes(child);
        });
      }
    },
    
    linkifyText(text) {
      // URL regex pattern - matches URLs starting with http://, https://, or www.
      // Updated to better handle UTF-8 characters in URLs
      const urlRegex = /(https?:\/\/|www\.)[^\s<][^\s<.,:;"')\]\}!?\u0000-\u001F\u007F-\u009F]*[^\s<.,:;"')\]\}!?]/gu;
      
      return text.replace(urlRegex, (url) => {
        // Ensure URL has proper protocol
        const href = url.startsWith('www.') ? 'https://' + url : url;
        
        try {
          // Validate URL encoding
          const encodedHref = encodeURI(decodeURI(href));
          
          // Create link with target="_blank" and rel="noopener" for security
          return `<a href="${encodedHref}" target="_blank" rel="noopener">${url}</a>`;
        } catch (e) {
          console.warn('Failed to process URL:', url, e);
          return url; // Return the original text if URL processing fails
        }
      });
    }
  }
};
</script>
