# Ignore design artifacts

- User requested removing `.impeccable` from the repository while preparing the API Keys checkpoint for commit and push.
- Removed the root and Console `.impeccable` directories from Git tracking, retaining their local contents. Replaced narrow generated-directory ignores with `.impeccable/`, which applies at any depth.
- These directories contain design-tool configuration, derived metadata, surface briefs and review screenshots. The application has no runtime references to them. Durable product/design documentation remains tracked.
- Verified root and nested artifact paths with `git check-ignore`, inspected the staged deletions, and ran `git diff --cached --check`. No runtime behavior changed.
