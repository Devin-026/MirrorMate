# Security and privacy

Diagnostics and repairs run on the current Mac. MirrorMate has no upload endpoint or telemetry. It uses the signed macOS tools already installed on the machine and does not execute user-supplied shell command text.

Cache backups can contain private continuity information. They stay under the current user’s Application Support folder and must not be committed or attached to public issues. The app’s own backup directories are created with owner-only access.

Repairs require explicit confirmation. Unknown formats, unreadable folders, unexpected symbolic links, and backups outside the configured backup root are rejected. A local lock prevents concurrent repair transactions. No root helper is installed.

Community artifacts are not Apple-notarized. A published checksum detects accidental download changes but is not a substitute for developer identity verification.

For a sensitive security report, contact the repository owner privately through GitHub if a private channel is available. Do not post cache files or credentials in a public issue. There is no promised response SLA.
