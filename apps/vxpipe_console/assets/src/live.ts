import { Socket } from "phoenix";
import { LiveSocket, type Hook } from "phoenix_live_view";

declare global {
  interface Window {
    liveSocket: LiveSocket;
  }
}

const metricPulse: Hook = {
  updated() {
    if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.el.animate(
        [
          { backgroundColor: "var(--green-soft)" },
          { backgroundColor: "transparent" },
        ],
        { duration: 450, easing: "cubic-bezier(0.16, 1, 0.3, 1)" },
      );
    }
  },
};

const hooks = { MetricPulse: metricPulse };

export function connectLiveView(): LiveSocket {
  const csrfToken = document
    .querySelector<HTMLMetaElement>('meta[name="csrf-token"]')
    ?.getAttribute("content");
  const socketPath = document.documentElement.getAttribute("phx-socket");

  if (!csrfToken || !socketPath) {
    throw new Error("LiveView page is missing its CSRF token or socket path");
  }

  const liveSocket = new LiveSocket(socketPath, Socket, {
    hooks,
    params: { _csrf_token: csrfToken },
  });

  liveSocket.connect();
  window.liveSocket = liveSocket;

  return liveSocket;
}

if (document.readyState === "loading") {
  document.addEventListener("DOMContentLoaded", connectLiveView, { once: true });
} else {
  connectLiveView();
}
