"use client";

import React from "react";
import styles from "./Button.module.css";

type ButtonVariant = "primary" | "secondary" | "outline" | "ghost" | "destructive";
type ButtonSize = "sm" | "md" | "lg" | "icon-sm" | "icon-md";

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: ButtonVariant;
  size?: ButtonSize;
  loading?: boolean;
  children?: React.ReactNode;
}

/**
 * Button — DESIGN.md §5.1
 *
 * Variants: primary, secondary, outline, ghost, destructive
 * Sizes: sm (32px), md (40px default), lg (48px), icon-sm, icon-md
 *
 * Uses globals.css CSS custom properties (--color-brand-*, --color-neutral-*, --color-error, --radius-*).
 */
export default function Button({
  variant = "primary",
  size = "md",
  loading = false,
  disabled,
  className = "",
  children,
  ...props
}: ButtonProps) {
  const isIcon = size === "icon-sm" || size === "icon-md";

  const classNames = [
    styles.btn,
    styles[variant],
    styles[size],
    className,
  ]
    .filter(Boolean)
    .join(" ");

  return (
    <button
      type="button"
      disabled={disabled || loading}
      className={classNames}
      {...props}
    >
      {loading && <span className={styles.spinner} aria-hidden="true" />}
      {!isIcon && children}
    </button>
  );
}
