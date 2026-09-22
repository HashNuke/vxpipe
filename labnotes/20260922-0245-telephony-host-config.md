# Telephony host config

## Goal

Make `TELEPHONY_HOST` the sole environment variable for the public telephony
origin used by callback and media URL generation.

## Progress

- Updated runtime configuration, focused runtime tests, sample environment, and
  telephony documentation to use `TELEPHONY_HOST`.
- Removed references to `VXPIPE_TELEPHONY_PUBLIC_BASE_URL`; this is a rename,
  not a compatibility alias.

## Verification

- The focused test invocation was blocked during application startup because the
  local PostgreSQL server rejected the configured connection before ExUnit ran.
