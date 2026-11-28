import { useEffect, useState } from "react";
import { CallConsole, type CallConsoleProps } from "@vxpipe/react";

/** Both operator routes reauthorize through their existing snapshot loader. */
export function InspectionConsole(props: CallConsoleProps) {
  const { controller } = props;
  const [unavailable, setUnavailable] = useState(false);
  const [retry, setRetry] = useState(0);

  useEffect(() => {
    const history = controller.history;
    if (!history) return;
    let current = true;
    let pending = false;
    let timer: number | undefined;

    function schedule() {
      window.clearTimeout(timer);
      const state = controller.details.getSnapshot().call.state;
      if (state !== "ended" && state !== "failed" && !document.hidden && navigator.onLine) {
        timer = window.setTimeout(refresh, 10_000);
      }
    }

    const refresh = async () => {
      if (pending || document.hidden) return;
      pending = true;
      window.clearTimeout(timer);
      try {
        await history.refresh();
        if (current) {
          setUnavailable(false);
          schedule();
        }
      } catch {
        // A new snapshot may be denied even if this tab previously had access.
        if (current) setUnavailable(true);
      } finally {
        pending = false;
      }
    };

    if (retry) void refresh();
    else schedule();
    window.addEventListener("online", refresh);
    document.addEventListener("visibilitychange", refresh);
    return () => {
      current = false;
      window.clearTimeout(timer);
      window.removeEventListener("online", refresh);
      document.removeEventListener("visibilitychange", refresh);
    };
  }, [controller, retry]);

  if (unavailable) return <div className="vx-inspection-state vx-inspection-error" role="alert">
    <p>Call inspection is unavailable.</p>
    <button type="button" onClick={() => setRetry(count => count + 1)}>Retry</button>
  </div>;
  return <CallConsole {...props} inspectConversation />;
}
