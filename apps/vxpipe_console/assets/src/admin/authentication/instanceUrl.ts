export function normalizeInstanceUrl(value: string): { url: string } | { error: string } {
  const invalid = { error: "Enter a valid HTTPS URL. HTTP is allowed for localhost." };
  const trimmed = value.trim();
  if (trimmed.length > 2048 || /[\s\\]/.test(trimmed) || !/^https?:\/\/[^/?#@]+(?:[/?#].*)?$/i.test(trimmed)) return invalid;
  try {
    const url = new URL(trimmed);
    const local = ["localhost", "127.0.0.1", "[::1]"].includes(url.hostname);
    if ((url.protocol !== "https:" && !(url.protocol === "http:" && local)) ||
        url.username || url.password || url.port === "0") return invalid;
    return { url: url.origin };
  } catch { return invalid; }
}
