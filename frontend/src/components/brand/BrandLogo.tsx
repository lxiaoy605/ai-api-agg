"use client";

import React from "react";

interface BrandLogoProps {
  variant?: "full" | "icon";
  className?: string;
}

/**
 * BrandLogo — AiflowHub network-node logo.
 *
 * - variant="full":  icon (24×24) + "aiflowhub" wordmark (default)
 * - variant="icon":  icon only, 24×24
 *
 * Replaces ⚡ emoji / Zap icon per DESIGN.md §1.2.
 */
export default function BrandLogo({
  variant = "full",
  className = "",
}: BrandLogoProps) {
  const icon = (
    <svg
      width="24"
      height="24"
      viewBox="0 0 24 24"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
      aria-label="AiflowHub logo"
      role="img"
      className="shrink-0"
    >
      <defs>
        <linearGradient id="brand-grad" x1="0%" y1="0%" x2="100%" y2="100%">
          <stop offset="0%" stopColor="#3B2FCE" />
          <stop offset="100%" stopColor="#7B61FF" />
        </linearGradient>
        <radialGradient id="brand-glow" cx="50%" cy="50%" r="50%">
          <stop offset="0%" stopColor="rgba(123,97,255,0.4)" />
          <stop offset="100%" stopColor="rgba(59,47,206,0)" />
        </radialGradient>
      </defs>

      {/* hexagon network node */}
      <polygon
        points="12,2 20.4,7 20.4,17 12,22 3.6,17 3.6,7"
        fill="url(#brand-grad)"
        stroke="url(#brand-grad)"
        strokeWidth="1.2"
      />

      {/* radiating connection lines */}
      <line x1="12" y1="2" x2="12" y2="1" stroke="#7B61FF" strokeWidth="1" strokeLinecap="round" />
      <line x1="20.4" y1="7" x2="21.8" y2="5.6" stroke="#7B61FF" strokeWidth="1" strokeLinecap="round" />
      <line x1="20.4" y1="17" x2="21.8" y2="18.4" stroke="#7B61FF" strokeWidth="1" strokeLinecap="round" />
      <line x1="12" y1="22" x2="12" y2="23" stroke="#7B61FF" strokeWidth="1" strokeLinecap="round" />
      <line x1="3.6" y1="17" x2="2.2" y2="18.4" stroke="#7B61FF" strokeWidth="1" strokeLinecap="round" />
      <line x1="3.6" y1="7" x2="2.2" y2="5.6" stroke="#7B61FF" strokeWidth="1" strokeLinecap="round" />

      {/* center glow */}
      <circle cx="12" cy="12" r="4" fill="url(#brand-glow)" />
      <circle cx="12" cy="12" r="2" fill="#C4B5FD" />
    </svg>
  );

  if (variant === "icon") {
    return <span className={className}>{icon}</span>;
  }

  return (
    <span className={`inline-flex items-center gap-2 ${className}`}>
      {icon}
      <span
        className="text-lg font-bold tracking-tight whitespace-nowrap"
        style={{
          background: "linear-gradient(135deg, #3B2FCE, #7B61FF)",
          WebkitBackgroundClip: "text",
          WebkitTextFillColor: "transparent",
        }}
      >
        aiflowhub
      </span>
    </span>
  );
}
