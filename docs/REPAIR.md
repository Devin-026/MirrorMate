# Repair design and validation

## Detection

The app queries the known `PairingRelationship.State` column read-only. On the validated macOS build, `1` represented incomplete pairing and `2` represented paired. These are observed implementation details, not a public Apple API. An SQL or permission failure must not be interpreted as “pairing is broken.”

The repair recommendation additionally requires at least two recent `noCompatiblePhone` failures and a supported Mac. A pending pairing with no repeated failures is allowed time to complete. A paired device is never automatically reset. Immediately before repair, diagnostics and schema preflight run again.

## Transaction

1. Acquire a current-user repair lock.
2. Validate the cache directory and create an owner-only backup directory with a versioned manifest.
3. Close iPhone Mirroring, unload `com.apple.replicatord`, and confirm its process has exited.
4. Move the complete cache directory to the backup, retaining its original files.
5. Re-register and start the system-provided LaunchAgent; macOS creates a new cache.
6. Recheck pairing and open Apple’s mirroring app. The user completes any authentication.

If startup fails after the move, stop the service, preserve any incomplete new cache, restore the original, and restart. If a rollback itself fails, preserve the files and show an actionable error. Do not overwrite a running service’s cache.

Restore validates the backup root, manifest, user ID, and cache presence. It stops the service and saves the current cache before bringing back the original. A failed restore attempts to restore the pre-restore state.

## Verified case

A Mac migrated from an Intel machine could discover its nearby iPhone but never completed mirroring setup. Wi-Fi, Bluetooth, macOS eligibility, and iCloud checks passed. Reboots and restarting the pairing daemon did not help. Resetting app-level selected-device preferences did not help and was reverted.

Rebuilding the system pairing cache changed the pairing state from `pairing` to `paired`. After the user completed first-time authorization, the system logged a remote connection and the first video frame; the user confirmed a visible phone screen. Both systems reported version 27.2.1. Migration was a likely trigger, not independently proven as the sole cause.

The app does not delete application preferences, keychain entries, or legacy caches as part of this repair.

## Test boundary

Automated tests exercise cache preservation, restore, failed service start rollback, failed restore rollback, path rejection, permission/format classification, and session disconnect handling. They use temporary folders and simulated services. Live read-only diagnostics and offscreen SwiftUI rendering can be run without resetting a working connection.
