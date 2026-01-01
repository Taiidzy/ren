import {
  createContext,
  useCallback,
  useContext,
  useEffect,
  useMemo,
  useRef,
  useState,
} from "react"
import { RETRY_BACKOFF_MS, WS_BASE_URL } from "@/config/env"
import { useAuth } from "@/context/auth-context"

export type RealtimeStatus = "disconnected" | "connecting" | "connected" | "error"

export type RealtimeClientMessage =
  | { type: "init"; contacts: number[] }
  | { type: "join_chat"; chat_id: number }
  | { type: "leave_chat"; chat_id: number }
  | { type: "typing"; chat_id: number; is_typing: boolean }
  | { type: "send_message"; chat_id: number; body: string }

export type RealtimeServerEvent =
  | { type: "presence"; user_id: number; status: "online" | "offline" }
  | {
      type: "message_new"
      chat_id: number
      message: {
        id: number
        chat_id: number
        sender_id: number
        body: string | null
        created_at: string
      }
    }
  | { type: "typing"; chat_id: number; user_id: number; is_typing: boolean }
  | { type: "ok" }
  | { type: "error"; error: string }

interface RealtimeContextValue {
  status: RealtimeStatus
  lastEvent: RealtimeServerEvent | null
  error: string | null
  setContacts: (contacts: number[]) => void
  joinChat: (chatId: number) => void
  leaveChat: (chatId: number) => void
  sendTyping: (chatId: number, isTyping: boolean) => void
  sendMessage: (chatId: number, body: string) => void
  reconnect: () => void
}

const RealtimeContext = createContext<RealtimeContextValue | undefined>(undefined)

function exponentialBackoff(previous: number) {
  if (!previous) return RETRY_BACKOFF_MS.min
  return Math.min(previous * 2, RETRY_BACKOFF_MS.max)
}

export function RealtimeProvider({ children }: { children: React.ReactNode }) {
  const { token } = useAuth()
  const [status, setStatus] = useState<RealtimeStatus>("disconnected")
  const [error, setError] = useState<string | null>(null)
  const [lastEvent, setLastEvent] = useState<RealtimeServerEvent | null>(null)
  const [contacts, setContactsState] = useState<number[]>([])

  const socketRef = useRef<WebSocket | null>(null)
  const reconnectTimeoutRef = useRef<number | null>(null)
  const backoffRef = useRef<number>(RETRY_BACKOFF_MS.min)
  const joinedChatsRef = useRef<Set<number>>(new Set())
  const manualCloseRef = useRef(false)

  const clearReconnectTimeout = () => {
    if (reconnectTimeoutRef.current) {
      window.clearTimeout(reconnectTimeoutRef.current)
      reconnectTimeoutRef.current = null
    }
  }

  const cleanupSocket = () => {
    if (socketRef.current) {
      manualCloseRef.current = true
      socketRef.current.close()
      socketRef.current = null
    }
    clearReconnectTimeout()
  }

  const sendPayload = useCallback((payload: RealtimeClientMessage) => {
    const socket = socketRef.current
    if (socket && socket.readyState === WebSocket.OPEN) {
      socket.send(JSON.stringify(payload))
    }
  }, [])

  const scheduleReconnect = useCallback(() => {
    if (!token || manualCloseRef.current) return
    clearReconnectTimeout()
    const timeout = backoffRef.current
    reconnectTimeoutRef.current = window.setTimeout(() => {
      backoffRef.current = exponentialBackoff(backoffRef.current)
      connect()
    }, timeout)
  }, [token])

  const connect = useCallback(() => {
    if (!token) {
      cleanupSocket()
      setStatus("disconnected")
      return
    }

    try {
      clearReconnectTimeout()
      manualCloseRef.current = false
      setStatus("connecting")
      setError(null)

      const protocols = [`Authorization: Bearer ${token}`]
      const socket = new WebSocket(WS_BASE_URL, protocols)
      socketRef.current = socket

      socket.addEventListener("open", () => {
        backoffRef.current = RETRY_BACKOFF_MS.min
        setStatus("connected")
        sendPayload({ type: "init", contacts })
        joinedChatsRef.current.forEach((chatId) => sendPayload({ type: "join_chat", chat_id: chatId }))
      })

      socket.addEventListener("message", (event) => {
        try {
          const data = JSON.parse(event.data) as RealtimeServerEvent
          setLastEvent(data)
          if (data.type === "error") {
            setError(data.error)
          }
        } catch (err) {
          console.error("Failed to parse WS message", err)
        }
      })

      socket.addEventListener("close", () => {
        socketRef.current = null
        if (manualCloseRef.current) {
          setStatus("disconnected")
          return
        }
        setStatus("disconnected")
        scheduleReconnect()
      })

      socket.addEventListener("error", (event) => {
        console.error("WebSocket error", event)
        setStatus("error")
        setError("Ошибка WebSocket-соединения")
        socket.close()
      })
    } catch (err) {
      console.error("WebSocket connection error", err)
      setStatus("error")
      setError(err instanceof Error ? err.message : "Не удалось установить соединение")
      scheduleReconnect()
    }
  }, [token, contacts, scheduleReconnect, sendPayload])

  useEffect(() => {
    connect()
    return () => {
      manualCloseRef.current = true
      cleanupSocket()
    }
  }, [connect])

  useEffect(() => {
    if (status === "connected") {
      sendPayload({ type: "init", contacts })
    }
  }, [contacts, status, sendPayload])

  useEffect(() => {
    const handleOnline = () => {
      if (status !== "connected") {
        connect()
      }
    }
    window.addEventListener("online", handleOnline)
    return () => window.removeEventListener("online", handleOnline)
  }, [connect, status])

  const setContacts = useCallback((ids: number[]) => {
    setContactsState(ids)
  }, [])

  const joinChat = useCallback(
    (chatId: number) => {
      joinedChatsRef.current.add(chatId)
      sendPayload({ type: "join_chat", chat_id: chatId })
    },
    [sendPayload],
  )

  const leaveChat = useCallback(
    (chatId: number) => {
      joinedChatsRef.current.delete(chatId)
      sendPayload({ type: "leave_chat", chat_id: chatId })
    },
    [sendPayload],
  )

  const sendTyping = useCallback(
    (chatId: number, isTyping: boolean) => {
      sendPayload({ type: "typing", chat_id: chatId, is_typing: isTyping })
    },
    [sendPayload],
  )

  const sendMessage = useCallback(
    (chatId: number, body: string) => {
      sendPayload({ type: "send_message", chat_id: chatId, body })
    },
    [sendPayload],
  )

  const reconnect = useCallback(() => {
    if (manualCloseRef.current) {
      manualCloseRef.current = false
    }
    connect()
  }, [connect])

  const value = useMemo<RealtimeContextValue>(
    () => ({ status, lastEvent, error, setContacts, joinChat, leaveChat, sendTyping, sendMessage, reconnect }),
    [status, lastEvent, error, setContacts, joinChat, leaveChat, sendTyping, sendMessage, reconnect],
  )

  return <RealtimeContext.Provider value={value}>{children}</RealtimeContext.Provider>
}

export function useRealtime() {
  const context = useContext(RealtimeContext)
  if (!context) {
    throw new Error("useRealtime must be used within RealtimeProvider")
  }
  return context
}
