const DEFAULT_API_BASE = "http://localhost:8000"
const DEFAULT_WS_BASE = "ws://localhost:8000"

export const API_BASE_URL = import.meta.env.VITE_API_URL ?? DEFAULT_API_BASE
export const WS_BASE_URL = import.meta.env.VITE_WS_URL ?? DEFAULT_WS_BASE

export const REQUEST_TIMEOUT_MS = 25_000

export const RETRY_BACKOFF_MS = {
  min: 2_000,
  max: 30_000,
}
