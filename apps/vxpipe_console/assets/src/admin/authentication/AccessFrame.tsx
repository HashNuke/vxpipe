import { useContext, type ReactNode } from "react";
import { LogOut, UserRound, Users, ShieldCheck } from "lucide-react";
import { AdminLayoutContext } from "../AdminLayoutContext";
import { AdminShell } from "../AdminShell";
import { Button } from "../Button";
import { canReadUsers } from "./access";
import type { Navigate, Role, Theme, User } from "./types";
export function AccessFrame({
  children,
  actor,
  role,
  path,
  onNavigate,
  onLogout,
  theme = "dark",
}: {
  children: ReactNode;
  actor?: User;
  role?: Role;
  path?: string;
  onNavigate?: Navigate;
  onLogout?: () => void;
  theme?: Theme;
}) {
  const embedded = useContext(AdminLayoutContext);
  const links = [
    ...(role && canReadUsers(role)
      ? [{ path: "/users", label: "Users", icon: Users }]
      : []),
    ...(role?.kind
      ? [{ path: "/roles", label: "Roles", icon: ShieldCheck }]
      : []),
    { path: "/account", label: "Account", icon: UserRound },
  ];
  return (
    <AdminShell
      theme={theme}
      headerActions={
        actor ? (
          <div className="access-session">
            <a
              href="/account"
              onClick={(event) => {
                event.preventDefault();
                onNavigate?.("/account");
              }}
            >
              {actor.email}
            </a>
            <Button
              type="button"
              variant="ghost"
              aria-label="Sign out"
              onClick={onLogout}
            >
              <LogOut size={16} aria-hidden />
            </Button>
          </div>
        ) : undefined
      }
    >
      {actor && !embedded ? (
        <nav className="access-nav" aria-label="Account administration">
          {links.map((link) => (
            <a
              key={link.path}
              href={link.path}
              aria-current={path?.startsWith(link.path) ? "page" : undefined}
              onClick={(event) => {
                event.preventDefault();
                onNavigate?.(link.path);
              }}
            >
              <link.icon size={16} aria-hidden />
              {link.label}
            </a>
          ))}
        </nav>
      ) : null}
      <div className="access-ui">{children}</div>
    </AdminShell>
  );
}
