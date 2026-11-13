import { TelnyxConnectionDialog as ConnectionDialog } from "../TelnyxConnectionDialog";
import type { StoryProviderDialogProps } from "./StoryProviderDialog";

export function TelnyxConnectionDialog(props: StoryProviderDialogProps) {
  return <ConnectionDialog {...props} onSave={changes => {
    if (changes.application_id !== undefined) props.onSaveApplication?.(changes.application_id ?? "");
    if (changes.credentials) props.onSubmit({ provider: "telnyx", values: {
      apiKey: changes.credentials.api_key ?? "", ...(changes.credentials.public_key ? { publicKey: changes.credentials.public_key } : {}),
    } });
    else if (changes.credentials === null) props.onUsePlatform?.("telnyx");
    else props.onClose();
  }} />;
}
