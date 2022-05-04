// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration
module.exports = {
  content: [
    './js/**/*.js',
    '../lib/*_web.ex',
    '../lib/*_web/**/*.*ex'
  ],
  theme: {
    extend: {
      colors: {
        current: 'white',
        grayscale: '#241824',
        grayscale600: '#7A727A',
        purple: '#8E2B77',
        purple50: '#F7E0F7',
        stone250: '#5325611a'
      }
    },
  },
  plugins: [
    require('@tailwindcss/forms'),
    require('tailwindcss-font-inter')
  ]
}
