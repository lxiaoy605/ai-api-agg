import { type ClassValue, clsx } from "clsx";
import { twMerge } from "tailwind-merge";

/**
 * CSS 类名合并工具，用于 shadcn/ui 组件
 */
export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs));
}
