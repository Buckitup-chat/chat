// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

const plugin = require('tailwindcss/plugin')

module.exports = {
  content: [
    './js/**/*.js',
    '../lib/*_web.ex',
    '../lib/*_web/**/*.*ex'
  ],
  theme: {
    extend: {
      maxWidth: {
        'xxs': '215px'
      },
      colors: {
        current: 'white',
        grayscale: '#241824',
        grayscale600: '#7A727A',
        purple: '#8E2B77',
        purple50: '#F7E0F7',
        stone250: '#5325611a'
      },
      keyframes: {
        'recording': {
          '0%, 100%': { opacity: 1 },
          '50%': { opacity: 0 },
        }
      },
      animation: {
        'recording': 'recording 2s normal infinite',
      }
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('tailwindcss-font-inter'),
    plugin(({ addVariant }) =>
      addVariant('phx-no-feedback', ['.phx-no-feedback&', '.phx-no-feedback &'])
    ),
    plugin(({ addVariant }) =>
      addVariant('phx-click-loading', [
        '.phx-click-loading&',
        '.phx-click-loading &',
      ])
    ),
    plugin(({ addVariant }) =>
      addVariant('phx-submit-loading', [
        '.phx-submit-loading&',
        '.phx-submit-loading &',
      ])
    ),
    plugin(({ addVariant }) =>
      addVariant('phx-change-loading', [
        '.phx-change-loading&',
        '.phx-change-loading &',
      ])
    ),
  ],
}
