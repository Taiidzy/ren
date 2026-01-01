import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useState,
} from "react"
import { useQueryClient } from "@tanstack/react-query"
import { authApi, userApi } from "@/services/chat-service"
import { tokenStorage } from "@/services/token-storage"
import type { LoginRequest, UserResponse } from "@/types/api"

export type AuthStatus = "idle" | "loading" | "authenticated" | "error"

interface AuthContextValue {
  user: UserResponse | null
  token: string | null
  status: AuthStatus
  error: string | null
  login: (credentials: LoginRequest) => Promise<void>
  logout: () => void
  refreshProfile: () => Promise<void>
}

const AuthContext = createContext<AuthContextValue | undefined>(undefined)

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const queryClient = useQueryClient()
  const [token, setToken] = useState<string | null>(() => tokenStorage.get())
  const [user, setUser] = useState<UserResponse | null>(null)
  const [status, setStatus] = useState<AuthStatus>(token ? "loading" : "idle")
  const [error, setError] = useState<string | null>(null)

  const loadProfile = useCallback(async () => {
    if (!token) {
      setUser(null)
      setStatus("idle")
      return
    }

    try {
      setStatus("loading")
      const profile = await userApi.me()
      setUser(profile)
      setStatus("authenticated")
      setError(null)
    } catch (err) {
      console.error("Failed to load profile", err)
      setStatus("error")
      setError(err instanceof Error ? err.message : "Не удалось загрузить профиль")
    }
  }, [token])

  useEffect(() => {
    loadProfile()
  }, [loadProfile])

  const login = useCallback(
    async (credentials: LoginRequest) => {
      setStatus("loading")
      setError(null)
      try {
        const response = await authApi.login(credentials)
        setToken(response.token)
        tokenStorage.set(response.token)
        setUser(response.user)
        setStatus("authenticated")
        queryClient.setQueryData(["auth", "me"], response.user)
      } catch (err) {
        const message = err instanceof Error ? err.message : "Ошибка авторизации"
        setStatus("error")
        setError(message)
        throw err
      }
    },
    [queryClient],
  )

  const logout = useCallback(() => {
    tokenStorage.clear()
    setToken(null)
    setUser(null)
    setStatus("idle")
    setError(null)
    queryClient.clear()
  }, [queryClient])

  const refreshProfile = useCallback(async () => {
    await loadProfile()
  }, [loadProfile])

  const value = useMemo<AuthContextValue>(
    () => ({ user, token, status, error, login, logout, refreshProfile }),
    [user, token, status, error, login, logout, refreshProfile],
  )

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) {
    throw new Error("useAuth must be used within AuthProvider")
  }
  return context
}
