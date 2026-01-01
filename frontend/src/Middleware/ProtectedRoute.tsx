import type { ReactNode } from "react"
import { Navigate } from "react-router-dom"
import { Spinner } from "@/components/ui/spinner"
import { useAuth } from "@/context/auth-context"

interface ProtectedRouteProps {
  children: ReactNode
}

const ProtectedRoute = ({ children }: ProtectedRouteProps) => {
  const { token, status, error } = useAuth()

  if (status === "loading") {
    return (
      <div className="flex min-h-screen flex-col items-center justify-center bg-slate-950 text-white">
        <Spinner />
        <p className="mt-4 text-sm text-white/70" role="status">
          Проверяем вашу сессию…
        </p>
      </div>
    )
  }

  if (!token || status === "error") {
    const message = error ?? "Требуется авторизация"
    return <Navigate to="/login" replace state={{ error: message }} />
  }

  return <>{children}</>
}

export default ProtectedRoute
