import React, { useCallback, useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { motion } from "framer-motion";
import AnimatedBackground from "@/components/animated-background";
import { Spinner } from "@/components/ui/spinner";

const Register = () => {
  const [loading, setLoading] = useState(false);

  const handleSubmit = useCallback((e?: React.FormEvent) => {
    // если передан event — предотвращаем отправку формы
    if (e && typeof (e as Event).preventDefault === "function") e.preventDefault();

    if (loading) return; // уже в процессе — игнорируем повторные клики

    setLoading(true);

    // эмуляция API-запроса: 5 секунд
    setTimeout(() => {
      setLoading(false);
      // сюда можно добавить навигацию или обработку результата
    }, 5000);
  }, [loading]);

  return (
    <AnimatedBackground>
      <div className="w-xl mx-auto p-4 flex items-center justify-center min-h-screen ">
        <motion.div
          initial={{ opacity: 0, y: 24 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.6, ease: "easeOut" }}
          className="
            w-full
            bg-white/15 
            backdrop-blur-lg 
            border border-white/20 
            rounded-3xl 
            shadow-[0_8px_32px_rgba(0,0,0,0.3)] 
            p-20
          "
        >
          {/* Заголовок */}
          <motion.h1
            initial={{ opacity: 0, y: 12 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ delay: 0.1, duration: 0.4 }}
            className="text-4xl font-bold text-white text-center drop-shadow-sm"
          >
            Регистрация
          </motion.h1>

          <motion.p
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.2, duration: 0.4 }}
            className="mt-2 text-sm text-gray-200/80 text-center"
          >
            Присоединяйтесь к нам!
          </motion.p>

          {/* Форма */}
          <form onSubmit={handleSubmit}>
            <motion.div
              initial="hidden"
              animate="show"
              variants={{
                hidden: { opacity: 0 },
                show: { opacity: 1, transition: { staggerChildren: 0.08 } },
              }}
              className="mt-10 space-y-5"
            >
              <motion.div variants={{ hidden: { opacity: 0, y: 8 }, show: { opacity: 1, y: 0 } }}>
                <label className="block text-sm font-medium text-gray-100 mb-1">
                  Логин
                </label>
                <Input
                  type="text"
                  name="login"
                  placeholder="Логин"
                  className="h-12 rounded-xl bg-white/10 border-white/20 text-white placeholder:text-gray-400 focus:ring-2 focus:ring-indigo-500"
                />
              </motion.div>

              <motion.div variants={{ hidden: { opacity: 0, y: 8 }, show: { opacity: 1, y: 0 } }}>
                <label className="block text-sm font-medium text-gray-100 mb-1">
                  Имя пользователя
                </label>
                <Input
                  type="text"
                  name="displayName"
                  placeholder="Имя пользователя"
                  className="h-12 rounded-xl bg-white/10 border-white/20 text-white placeholder:text-gray-400 focus:ring-2 focus:ring-indigo-500"
                />
              </motion.div>

              <motion.div variants={{ hidden: { opacity: 0, y: 8 }, show: { opacity: 1, y: 0 } }}>
                <label className="block text-sm font-medium text-gray-100 mb-1">
                  Пароль
                </label>
                <Input
                  type="password"
                  name="password"
                  placeholder="Пароль"
                  className="h-12 rounded-xl bg-white/10 border-white/20 text-white placeholder:text-gray-400 focus:ring-2 focus:ring-indigo-500"
                />
              </motion.div>

              <motion.div variants={{ hidden: { opacity: 0, y: 8 }, show: { opacity: 1, y: 0 } }}>
                <label className="block text-sm font-medium text-gray-100 mb-1">
                  Подтверждение пароля
                </label>
                <Input
                  type="password"
                  name="passwordConfirm"
                  placeholder="Подтверждение пароля"
                  className="h-12 rounded-xl bg-white/10 border-white/20 text-white placeholder:text-gray-400 focus:ring-2 focus:ring-indigo-500"
                />
              </motion.div>

              <motion.div variants={{ hidden: { opacity: 0, y: 8 }, show: { opacity: 1, y: 0 } }}>
                <Button
                  type="submit"
                  className={`w-full h-12 rounded-xl text-base font-medium cursor-pointer transition-all bg-indigo-600 hover:bg-indigo-700`}
                  disabled={loading}
                >
                  {loading && <Spinner />}
                  <span className="align-middle">{loading ? "Регистрация..." : "Зарегистрироваться"}</span>
                </Button>
              </motion.div>
            </motion.div>
          </form>

          <motion.p
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.35, duration: 0.4 }}
            className="mt-8 text-center text-sm text-gray-300"
          >
            Уже есть аккаунта?{" "}
            <a
              href="/login"
              className="text-indigo-400 hover:text-indigo-300 hover:underline transition-colors"
            >
              Войти
            </a>
          </motion.p>
        </motion.div>
      </div>
    </AnimatedBackground>
  );
};

export default Register;
