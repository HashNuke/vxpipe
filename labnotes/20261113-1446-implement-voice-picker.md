# Implement voice picker

## Scope and branch

Merged committed QA into main at `1b51f116` and pushed main. Uncommitted QA
changes were left intact. Implement the provider voice picker milestone here,
using the reviewed component and existing effective credential resolver.

## Backend checkpoint

- Added authoring-only catalog describe/list/get with finite model reuse, bounded
  HTTP responses/timeouts and strict queries. No call startup dependency.
- ElevenLabs TTS uses authenticated v2 search and direct v1 ID lookup. Official
  docs describe `high_quality_base_model_ids` as recommendations, so these do not
  exclude voices; professional fine-tuning readiness is checked for the model.
- Calls enforces tenant read permission and existing platform binding rules on
  every request. Console routes use the same permission, JSON-only responses and
  no-store. The first endpoint run exposed the required route-permission map
  addition; adding routes alone correctly remained forbidden.
- Red/green: Engine 8, Calls 6, Console endpoints 2 focused tests. Synthetic
  fixtures only; no provider account requests, paid synthesis or telephony.

## Remaining

Production UI/client scope, remaining provider catalogs, browser acceptance and
final milestone gates. No deployment is claimed. Environment files were not read.
