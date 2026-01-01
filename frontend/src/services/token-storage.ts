const TOKEN_KEY = "messenger_token"

function getStorage(): Storage | null {
  if (typeof window === "undefined") {
    return null
  }

  return window.localStorage
}

export const tokenStorage = {
  get(): string | null {
    try {
      return getStorage()?.getItem(TOKEN_KEY) ?? null
    } catch {
      return null
    }
  },
  set(token: string) {
    try {
      getStorage()?.setItem(TOKEN_KEY, token)
    } catch {
      /* ignore */
    }
  },
  clear() {
    try {
      getStorage()?.removeItem(TOKEN_KEY)
    } catch {
      /* ignore */
    }
  },
}
