export function humanizeIdentifier(value: string) {
  const words = value.replaceAll("_", " ").replaceAll("-", " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
}
