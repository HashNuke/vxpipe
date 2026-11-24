# Ringing handset hangup

The live handset runner previously offered ring-out and answered-bridge modes. It now has an explicit hangup_during_ring mode for the remaining caller-abandonment gate. The test waits for the durable dial intent and the linked owner’s validated carrier leg registration before cueing the operator to hang up the handset. It leaves the destination unanswered and checks abandonment, caller and peer terminal usage, and managed cleanup. A bridge or callback announcement fails acceptance.

The runner requires a coordinated call. The two-number automatic fixture would call back its own originating number, which the recovery destination policy excludes. The offline fixture suite verifies configuration and accounting. An actual caller-abandonment result remains outstanding.
