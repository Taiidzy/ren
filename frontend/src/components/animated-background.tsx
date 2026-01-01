// AnimatedBreathingBackground.tsx
import type { PropsWithChildren } from "react";
import { motion } from "framer-motion";

/**
 * Static linear gradient background with a subtle "breathing" animation
 * that scales + changes opacity slightly using framer-motion.
 *
 * Usage: <AnimatedBreathingBackground><YourApp/></AnimatedBreathingBackground>
 */

type Props = PropsWithChildren<{
  className?: string;
  // breathing controls:
  duration?: number; // seconds for one inhale/exhale cycle (full back-and-forth)
  scaleAmount?: number; // final scale (1.02 => ±2%)
  opacityRange?: [number, number]; // [min, max] opacity for the animated layer
}>;

export function AnimatedBreathingBackground({
  children,
  className,
  duration = 4.5,
  scaleAmount = 1.02,
  opacityRange = [0.86, 1],
}: Props) {
  // motion keyframes: scale goes 1 -> scaleAmount -> 1 (using repeatType: "mirror" gives smooth cycle)
  const transition = {
    duration,
    repeat: Infinity,
    repeatType: "mirror" as const,
    ease: "easeInOut" as const,
  };

  return (
    <div className={`relative min-h-screen w-full overflow-hidden bg-black ${className ?? ""}`}>
      {/* Animated gradient layer — we animate the wrapper for a breathing effect */}
      <motion.div
        aria-hidden
        className="pointer-events-none absolute inset-0 z-0"
        initial={{ scale: 1, opacity: opacityRange[1] }}
        animate={{ scale: [1, scaleAmount], opacity: [opacityRange[1], opacityRange[0]] }}
        transition={transition}
        style={{
          // Linear gradient from bottom-left (dark) to top-right (wine red)
          background: `linear-gradient(
            40deg,
            rgba(6, 20, 44, 1) 0%,
            rgba(25, 30, 50, 1) 25%,
            rgba(80, 0, 30, 0.9) 70%,
            rgba(155, 10, 54, 0.95) 100%
          )`,
          transformOrigin: "50% 50%", // scale from center — change to "10% 90%" to bias toward bottom-left etc.
          willChange: "transform, opacity",
        }}
      />

      {/* Soft vignette overlay (optionally animated slightly out-of-phase for depth) */}
      <motion.div
        aria-hidden
        className="pointer-events-none absolute inset-0 z-5"
        initial={{ opacity: 0.55 }}
        animate={{ opacity: [0.55, 0.48] }}
        transition={{ ...transition, duration: duration * 1.1 }}
        style={{
          background: "radial-gradient(1200px 600px at 50% 50%, rgba(0,0,0,0) 25%, rgba(0,0,0,0.55) 100%)",
          mixBlendMode: "multiply",
          willChange: "opacity",
        }}
      />

      {/* Content */}
      <div className="relative z-10">{children}</div>
    </div>
  );
}

export default AnimatedBreathingBackground;
