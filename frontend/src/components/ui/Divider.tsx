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
          "inline-block h-full min-h-[1em] w-px shrink-0 self-stretch bg-neutral-600",
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
          className="h-px flex-1 bg-neutral-600"
        />
        <span className="flex-shrink-0 text-xs text-neutral-400">
          {children}
        </span>
        <div
          role="separator"
          aria-orientation="horizontal"
          className="h-px flex-1 bg-neutral-600"
        />
      </div>
    );
  }

  /* Default horizontal */
  return (
    <hr
      role="separator"
      aria-orientation="horizontal"
      className={cn("border-0 h-px bg-neutral-600", className)}
    />
  );
}
