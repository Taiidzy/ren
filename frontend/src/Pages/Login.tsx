import { useEffect, useMemo, useState } from "react"
import { Link, useLocation, useNavigate } from "react-router-dom"
import { useMutation } from "@tanstack/react-query"
import { Button } from "@/components/ui/button"
import { Checkbox } from "@/components/ui/checkbox"
import { Input } from "@/components/ui/input"
import { Spinner } from "@/components/ui/spinner"
import { AuthLayout } from "@/layouts/auth-layout"
import { useAuth } from "@/context/auth-context"

const Login = () => {
  const navigate = useNavigate()
  const location = useLocation()
  const { login } = useAuth()

  const [loginField, setLoginField] = useState("")
  const [password, setPassword] = useState("")
  const [rememberMe, setRememberMe] = useState(true)
  const [formError, setFormError] = useState<string | null>(null)

  const mutation = useMutation({
    mutationFn: () => login({ login: loginField.trim(), password, remember_me: rememberMe }),
    onSuccess: () => {
      navigate("/", { replace: true })
    },
    onError: (error) => {
      const message = error instanceof Error ? error.message : "Не удалось войти"
      setFormError(message)
    },
  })

  useEffect(() => {
    const navError = (location.state as { error?: string } | null)?.error
    if (navError) {
      setFormError(navError)
    }
  }, [location.state])

  const isSubmitDisabled = useMemo(() => {
    return loginField.trim().length === 0 || password.length < 6 || mutation.isPending
  }, [loginField, password, mutation.isPending])

  const handleSubmit = (event: React.FormEvent<HTMLFormElement>) => {
    event.preventDefault()
    setFormError(null)
    mutation.mutate()
  }

  return (
    <AuthLayout title="Вход" subtitle="Рады видеть вас снова!">
      <form className="space-y-5" onSubmit={handleSubmit} noValidate>
        <div className="space-y-2">
          <label htmlFor="login" className="text-sm font-medium text-white">
            Логин
          </label>
          <Input
            id="login"
            name="login"
            type="text"
            autoComplete="username"
            placeholder="username"
            value={loginField}
            onChange={(event) => setLoginField(event.target.value)}
            aria-invalid={Boolean(formError)}
            required
          />
        </div>

        <div className="space-y-2">
          <label htmlFor="password" className="text-sm font-medium text-white">
            Пароль
          </label>
          <Input
            id="password"
            name="password"
            type="password"
            autoComplete="current-password"
            placeholder="••••••••"
            value={password}
            onChange={(event) => setPassword(event.target.value)}
            minLength={6}
            required
          />
        </div>

        <label className="flex items-center gap-2 text-sm text-white/80">
          <Checkbox
            checked={rememberMe}
            onCheckedChange={(checked) => setRememberMe(Boolean(checked))}
            aria-label="Запомнить меня"
          />
          Запомнить меня (365 дней)
        </label>

        {formError && (
          <div role="alert" className="rounded-xl border border-red-500/40 bg-red-500/10 px-3 py-2 text-sm text-red-200">
            {formError}
          </div>
        )}

        <Button type="submit" className="w-full" disabled={isSubmitDisabled}>
          {mutation.isPending && <Spinner className="mr-2" />}
          {mutation.isPending ? "Входим…" : "Войти"}
        </Button>
      </form>

      <p className="text-center text-sm text-white/70">
        Нет аккаунта?{" "}
        <Link to="/register" className="text-indigo-300 underline-offset-4 hover:underline">
          Зарегистрируйтесь
        </Link>
      </p>
    </AuthLayout>
  )
}

export default Login;
