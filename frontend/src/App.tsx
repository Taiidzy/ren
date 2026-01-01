import { Suspense, lazy } from "react"
import { BrowserRouter as Router, Routes, Route, Navigate } from "react-router-dom"
import ProtectedRoute from "./Middleware/ProtectedRoute"
import { Spinner } from "@/components/ui/spinner"

const Login = lazy(() => import("./Pages/Login"))
const Register = lazy(() => import("./Pages/Register"))
const Home = lazy(() => import("./Pages/Home"))

const Fallback = () => (
  <div className="flex min-h-screen items-center justify-center bg-slate-950">
    <Spinner className="text-white" />
    <p className="ml-3 text-white/80">Загружаем интерфейс…</p>
  </div>
)

function App() {
  return (
    <Router>
      <Suspense fallback={<Fallback />}>
        <Routes>
          <Route path="/login" element={<Login />} />
          <Route path="/register" element={<Register />} />
          <Route
            path="/"
            element={
              <ProtectedRoute>
                <Home />
              </ProtectedRoute>
            }
          />
          <Route
            path="/chat/:chatId"
            element={
              <ProtectedRoute>
                <Home />
              </ProtectedRoute>
            }
          />
          <Route path="*" element={<Navigate to="/" replace />} />
        </Routes>
      </Suspense>
    </Router>
  )
}

export default App
