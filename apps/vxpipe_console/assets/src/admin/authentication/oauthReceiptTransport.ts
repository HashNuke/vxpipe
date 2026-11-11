export type OAuthCompletion = {
  request_id: string;
  callback: string;
  expires_at: string | null;
};

/** Reserve a receipt window during the click; a blocked window keeps the native redirect. */
export function prepareReceipt(form: HTMLFormElement, requestId: string): boolean {
  const target = `vxpipe-consent-${requestId}`;
  try {
    const receipt = window.open("", target);
    if (!receipt || receipt.closed) return false;
  } catch { return false; }
  const presentation = document.createElement("input");
  presentation.type = "hidden";
  presentation.name = "presentation";
  presentation.value = "receipt";
  form.append(presentation);
  form.target = target;
  return true;
}

/** The server supplies the validated callback. Never redirect an unrelated opener. */
export function deliverCallback(completion: OAuthCompletion, receipt: Window = window): void {
  const original = receipt.opener as Window | null;
  receipt.opener = null;
  try {
    if (original && !original.closed && original.location.origin === receipt.location.origin &&
        original.location.pathname === `/oauth/authorize/${completion.request_id}`) {
      original.location.replace(completion.callback);
      return;
    }
  } catch { /* A closed or cross-origin opener cannot own this handoff. */ }
  receipt.location.replace(completion.callback);
}
