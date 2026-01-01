import type { PropsWithChildren } from "react"
import AnimatedBackground from "@/components/animated-background"

export function AuthLayout({ title, subtitle, children }: PropsWithChildren<{ title: string; subtitle?: string }>) {
  return (
    <AnimatedBackground>
      <div className="flex min-h-screen items-center justify-center px-4 py-8">
        <section className="w-full max-w-md rounded-3xl border border-white/20 bg-white/5 p-10 text-white shadow-2xl backdrop-blur-xl">
          <header className="space-y-2 text-center">
            <h1 className="text-3xl font-semibold tracking-tight">{title}</h1>
            {subtitle && <p className="text-sm text-white/70">{subtitle}</p>}
          </header>
          <div className="mt-8 space-y-6">{children}</div>
        </section>
      </div>
    </AnimatedBackground>
  )
}
