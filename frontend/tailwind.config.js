/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,jsx}'],
  theme: {
    extend: {
      colors: {
        primary: { DEFAULT: '#2563EB', hover: '#1D4ED8' },
        secondary: '#64748B',
        success: '#16A34A',
        warning: '#D97706',
        danger: '#DC2626',
        surface: '#FFFFFF',
        canvas: '#F8FAFC',
        border: '#E2E8F0',
        ink: { DEFAULT: '#0F172A', muted: '#64748B' },
        site1: '#2563EB',
        site2: '#7C3AED',
      },
      fontFamily: {
        sans: ['Inter', 'Noto Sans Thai', 'sans-serif'],
      },
      borderRadius: {
        DEFAULT: '6px',
      },
    },
  },
  plugins: [],
};
