import React from "react";
import styles from "./Card.module.css";

type CardVariant = "default" | "hover" | "glass";

interface CardProps {
  variant?: CardVariant;
  className?: string;
  children: React.ReactNode;
}

/**
 * Card — DESIGN.md §5.2
 *
 * Variants:
 * - default: surface-elevated bg, neutral-600 border, 12px radius
 * - hover:   default + hover border/shadow (e.g. model cards)
 * - glass:   surface-glass bg, semi-transparent border, backdrop-blur, 16px radius
 *
 * Sub-components: Card.Header, Card.Content, Card.Footer (24px padding per spec).
 */
function Card({ variant = "default", className = "", children }: CardProps) {
  const classNames = [styles.card, variant !== "default" && styles[variant], className]
    .filter(Boolean)
    .join(" ");

  return <div className={classNames}>{children}</div>;
}

/* ---------- Sub-components ---------- */

function CardHeader({
  className = "",
  children,
}: {
  className?: string;
  children: React.ReactNode;
}) {
  return <div className={`${styles.header} ${className}`}>{children}</div>;
}

function CardContent({
  className = "",
  children,
}: {
  className?: string;
  children: React.ReactNode;
}) {
  return <div className={`${styles.content} ${className}`}>{children}</div>;
}

function CardFooter({
  className = "",
  children,
}: {
  className?: string;
  children: React.ReactNode;
}) {
  return <div className={`${styles.footer} ${className}`}>{children}</div>;
}

Card.Header = CardHeader;
Card.Content = CardContent;
Card.Footer = CardFooter;

export default Card;
