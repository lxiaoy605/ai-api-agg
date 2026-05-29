"use client";

import { cn } from "@/lib/utils";

/* ------------------------------------------------------------------ */
/*  Spinner — rotating ring, brand-600, pure CSS                       */
/* ------------------------------------------------------------------ */
export function Spinner({ className }: { className?: string }) {
  return (
    <svg
      className={cn("animate-spin", className)}
      xmlns="http://www.w3.org/2000/svg"
      fill="none"
      viewBox="0 0 24 24"
      width="24"
      height="24"
      aria-hidden="true"
    >
      <circle
        cx="12"
        cy="12"
        r="10"
        stroke="currentColor"
        strokeWidth="2"
        opacity="0.15"
      />
      <path
        d="M12 2a10 10 0 0 1 10 10"
        stroke="currentColor"
        strokeWidth="2"
        strokeLinecap="round"
        className="text-brand-600"
      />
    </svg>
  );
}

/* ------------------------------------------------------------------ */
/*  Skeleton — pulsing placeholder, pure CSS                           */
/* ------------------------------------------------------------------ */
export function Skeleton({ className }: { className?: string }) {
  return (
    <div
      className={cn(
        "animate-pulse rounded bg-neutral-700",
        className,
      )}
      aria-busy="true"
      role="status"
    />
  );
}
