import { Slot } from "@radix-ui/react-slot";
import { cva, type VariantProps } from "class-variance-authority";
import type { ButtonHTMLAttributes } from "react";

import { classNames } from "./classNames";

const buttonStyles = cva(
  "inline-flex min-h-9 items-center justify-center gap-2 rounded-md border px-3 text-sm font-medium transition-colors focus-visible:outline-2 disabled:pointer-events-none disabled:opacity-45",
  {
    variants: {
      variant: {
        default:
          "border-[var(--admin-line)] bg-[var(--admin-panel)] text-[var(--admin-ink)] hover:bg-[var(--admin-soft)]",
        ghost:
          "border-transparent bg-transparent text-[var(--admin-muted)] hover:bg-[var(--admin-soft)] hover:text-[var(--admin-ink)]",
      },
    },
    defaultVariants: { variant: "default" },
  },
);

export function Button({
  asChild = false,
  className,
  variant,
  ...props
}: ButtonHTMLAttributes<HTMLButtonElement> &
  VariantProps<typeof buttonStyles> & { asChild?: boolean }) {
  const Component = asChild ? Slot : "button";
  return (
    <Component
      className={classNames(buttonStyles({ variant }), className)}
      {...props}
    />
  );
}
