import { computed } from 'vue'

type DarkMode = 'light' | 'dark'

function getPreferredDarkMode(): DarkMode {
  if (typeof document !== 'undefined' && document.documentElement.classList.contains('dark')) {
    return 'dark'
  }

  if (typeof localStorage !== 'undefined') {
    const storedMode = localStorage.getItem('theme') || localStorage.getItem('darkMode')
    if (storedMode === 'dark') {
      return 'dark'
    }
  }

  if (typeof window !== 'undefined' && window.matchMedia?.('(prefers-color-scheme: dark)').matches) {
    return 'dark'
  }

  return 'light'
}

export function useRootSetting() {
  const getDarkMode = computed<DarkMode>(() => getPreferredDarkMode())

  return {
    getDarkMode,
  }
}
