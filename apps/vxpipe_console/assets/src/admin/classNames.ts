import { clsx, type ClassValue } from "clsx";
import { twMerge } from "tailwind-merge";

export function classNames(...values: ClassValue[]) {
  return twMerge(clsx(values));
}
