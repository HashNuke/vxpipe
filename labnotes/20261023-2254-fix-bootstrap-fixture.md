# Fix bootstrap proof fixture

- During verification of the editor work, the persistence proof-failure test failed against a fresh database. Fresh installations use first-run mode, so supplying an invalid proof did not enter the operator-required proof branch that the test intended to exercise.
- The pending correction explicitly switches the fixture installation to operator-required mode before invoking complete_with_proof, and requires the precise invalid_proof result.
- This changes the test setup only. Production bootstrap and authentication behavior remain unchanged.
- Verified in the focused reproduction, the full persistence suite (281 tests, zero failures), and the subsequent successful umbrella suite (3,811 reported tests, zero failures).
- Reviewed for a separate commit from the editor feature and dependency upgrades at the user's request to commit the pending work.
