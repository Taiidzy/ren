import { API_BASE_URL, REQUEST_TIMEOUT_MS } from "@/config/env"
import { tokenStorage } from "@/services/token-storage"

type HttpMethod = "GET" | "POST" | "PATCH" | "DELETE"

type RequestOptions<TBody> = {
  method?: HttpMethod
  body?: TBody
  signal?: AbortSignal
  headers?: HeadersInit
}

export async function httpRequest<TResponse, TBody = unknown>(
  path: string,
  options: RequestOptions<TBody> = {},
): Promise<TResponse> {
  const controller = new AbortController()
  const timeoutId = setTimeout(() => controller.abort(), REQUEST_TIMEOUT_MS)

  const token = tokenStorage.get()

  const response = await fetch(`${API_BASE_URL}${path}`, {
    method: options.method ?? "GET",
    headers: {
      "Content-Type": "application/json",
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...options.headers,
    },
    body: options.body ? JSON.stringify(options.body) : undefined,
    signal: options.signal ?? controller.signal,
  })
  clearTimeout(timeoutId)

  const data = await response.json().catch(() => null)

  if (!response.ok) {
    const error = (data as { error?: string } | null)?.error ?? "Неизвестная ошибка"
    throw new Error(error)
  }

  return data as TResponse
}
