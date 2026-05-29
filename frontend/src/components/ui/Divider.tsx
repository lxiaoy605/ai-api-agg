import { cn } from "@/lib/utils";

/* ------------------------------------------------------------------ */
/*  Divider — DESIGN.md §5.9                                           */
/* ------------------------------------------------------------------ */
type DividerProps = {
  orientation?: "horizontal" | "vertical";
  className?: string;
  children?: React.ReactNode;
};

export function Divider({
  orientation = "horizontal",
  className,
  children,
}: DividerProps) {
  /* Vertical divider */
  if (orientation === "vertical") {
    return (
      <div
        role="separator"
        aria-orientation="vertical"
        className={cn(
          "inline-block h-full min-h-[1em] w-px shrink-0 self-stretch bg-[var(--border-color)]",
          className,
        )}
      />
    );
  }

  /* Horizontal with text label */
  if (children) {
    return (
      <div className={cn("flex items-center gap-3", className)}>
        <div
          role="separator"
          aria-orientation="horizontal"
          className="h-px flex-1 bg-[var(--border-color)]"
        />
        <span className="flex-shrink-0 text-xs text-[var(--muted-text)]">
          {children}
        </span>
        <div
          role="separator"
          aria-orientation="horizontal"
          className="h-px flex-1 bg-[var(--border-color)]"
        />
      </div>
    );
  }

  /* Default horizontal */
  return (
    <hr
      role="separator"
      aria-orientation="horizontal"
      className={cn("border-0 h-px bg-[var(--border-color)]", className)}
    />
  );
}
