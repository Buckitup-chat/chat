<!--
  LinkedText component
  - Takes text content and converts URLs to clickable links
  - Preserves existing <a> tags in the input
  - All links have target="_blank" to open in new tab
  - Supports custom styling through class props
  - Improved UTF-8/Cyrillic text handling
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
    // Fix UTF-8 encoding in the DOM before processing
    this.fixUtf8Encoding();
    
    // Process content for URLs
    this.processContent();
  },
  methods: {  
    /**
     * Fixes the UTF-8 encoding issue by directly updating the DOM content
     * using the proper base64 decoding method for non-ASCII characters
     */
    fixUtf8Encoding() {
      const parentEl = this.$el.parentElement;
      if (!parentEl || !parentEl.hasAttribute('data-slots')) {
        return;
      }
      
      try {
        // Get the base64-encoded data
        const dataSlots = parentEl.getAttribute('data-slots');
        const parsed = JSON.parse(dataSlots);
        
        if (!parsed.default) {
          return;
        }
        
        // Use UTF-8 aware decoding method with modern TextDecoder API
        const base64Decoded = atob(parsed.default);
        // Convert to byte array for TextDecoder
        const bytes = new Uint8Array(base64Decoded.length);
        for (let i = 0; i < base64Decoded.length; i++) {
          bytes[i] = base64Decoded.charCodeAt(i);
        }
        const properlyDecoded = new TextDecoder('utf-8').decode(bytes);
        
        // If the content is already in the DOM but encoded incorrectly,
        // we can fix it by replacing the innerHTML
        if (this.$el.innerHTML && this.$el.innerHTML.indexOf('Ð') >= 0) {
          // Parse the properly decoded HTML and use it to replace the current content
          const tempDiv = document.createElement('div');
          tempDiv.innerHTML = properlyDecoded;
          
          // Clear existing content
          while (this.$el.firstChild) {
            this.$el.removeChild(this.$el.firstChild);
          }
          
          // Add properly decoded content
          while (tempDiv.firstChild) {
            this.$el.appendChild(tempDiv.firstChild);
          }
        }
      } catch (e) {
        // Silent error handling - we'll let the component continue even if encoding fix fails
      }
    },
    
    updated() {
      // Re-process content when component is updated
      this.processContent();
    },
    
    processContent() {
      if (!this.$refs.contentContainer) return;
      
      // Process all text nodes in the DOM, ignoring text inside <a> tags
      this.processTextNodes(this.$refs.contentContainer);
    },
    
    processTextNodes(node) {
      // If this is a text node, process it
      if (node.nodeType === Node.TEXT_NODE) {
        // Skip empty text nodes
        if (!node.textContent.trim()) return;
        
        // Get original text and create text ranges
        const original = node.textContent;
        const ranges = this.findUrlRanges(original);
        
        // If no URLs found, leave text as is
        if (ranges.length === 0) {
          return;
        }
        
        // Create document fragment
        const fragment = document.createDocumentFragment();
        let lastIndex = 0;
        
        // Process each URL range
        ranges.forEach(range => {
          // Add text before URL
          if (range.start > lastIndex) {
            const textBefore = original.substring(lastIndex, range.start);
            fragment.appendChild(document.createTextNode(textBefore));
          }
          
          // Create link element directly
          try {
            const link = document.createElement('a');
            const urlText = original.substring(range.start, range.end);
            
            // Set href with protocol if needed
            let href;
            if (urlText.startsWith('www.')) {
              href = 'https://' + urlText;
            } else {
              href = urlText;
            }
            
            // Set href attribute
            link.href = href;
            
            // Use createTextNode to preserve encoding
            link.appendChild(document.createTextNode(urlText));
            
            link.target = '_blank';
            link.rel = 'noopener';
            
            fragment.appendChild(link);
            lastIndex = range.end;
          } catch (e) {
            // Silently handle errors creating links
          }
        });
        
        // Add remaining text after last URL
        if (lastIndex < original.length) {
          const textAfter = original.substring(lastIndex);
          fragment.appendChild(document.createTextNode(textAfter));
        }
        
        // Replace original node with fragment
        node.parentNode.replaceChild(fragment, node);
        return;
      }
      
      // If it's an element node, check if it's an <a> tag
      if (node.nodeType === Node.ELEMENT_NODE) {
        // Skip processing inside <a> tags
        if (node.nodeName.toLowerCase() === 'a') {
          return;
        }
        
        // Process child nodes recursively
        const children = Array.from(node.childNodes);
        children.forEach(child => {
          this.processTextNodes(child);
        });
      }
    },
    
    // Find URL ranges in text without modifying the original text
    findUrlRanges(text) {
      // Array to store URL ranges {start, end}
      const ranges = [];
      
      // We'll use a safer approach by scanning character by character
      let i = 0;
      while (i < text.length) {
        // Look for URL protocol patterns at current position
        const isHttps = text.substr(i, 8).toLowerCase() === 'https://';
        const isHttp = text.substr(i, 7).toLowerCase() === 'http://';
        const isWww = text.substr(i, 4).toLowerCase() === 'www.';
        
        // If we find a URL pattern start
        if (isHttps || isHttp || isWww) {
          // Mark the start position
          const urlStart = i;
          let urlEnd = i;
          
          // Protocol length
          if (isHttps) urlEnd += 8;
          else if (isHttp) urlEnd += 7;
          else if (isWww) urlEnd += 4;
          
          // Find the end of the URL by looking for whitespace or certain punctuation
          // but we need to handle URLs that contain valid punctuation
          let inParenthesis = 0;
          let inBrackets = 0;
          
          // Scan forward until we hit a terminating character
          while (urlEnd < text.length) {
            const c = text.charAt(urlEnd);
            
            // Handle nested structures
            if (c === '(') inParenthesis++;
            if (c === ')' && inParenthesis > 0) inParenthesis--;
            if (c === '[') inBrackets++;
            if (c === ']' && inBrackets > 0) inBrackets--;
            
            // Break on whitespace
            if (/\s/.test(c)) break;
            
            // Break on certain punctuation if not inside a structure
            if (inParenthesis === 0 && inBrackets === 0) {
              // Handle trailing punctuation that shouldn't be part of the URL
              if (/[.,;:!?]$/.test(c) && 
                  (urlEnd + 1 === text.length || /\s/.test(text.charAt(urlEnd + 1)))) {
                break;
              }
            }
            
            urlEnd++;
          }
          
          // Add the URL range
          ranges.push({
            start: urlStart,
            end: urlEnd
          });
          
          // Continue search from end of this URL
          i = urlEnd;
        } else {
          i++;
        }
      }
      
      // Return all found URL ranges
      return ranges;
    }
  }
};
</script>
