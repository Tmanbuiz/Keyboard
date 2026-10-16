# Technical audit remediation — October 16, 2026

The PDF audit referenced the private Worker template. Production uses `Backend/public-worker.mjs`, verified Apple identities, per-device opaque sessions stored as hashes, account revocation and transactional per-user/global quotas. The private template is not the deployed entry point.

## Changes

- Network responses are bounded as chunks arrive. Full GIFs stop at 8 MB, previews at 3 MB, search JSON at 500 KB and AI/account JSON at 100 KB. A shared gate allows four requests at once; cancelled waiting requests release their place. Redirects are rejected before credentials or selected text can be forwarded.
- GIF downloads validate the trusted media URL, actual image type, dimensions, frame count and aggregate frame pixels without decoding full animation frames. Previews downsample the first frame to 256 pixels and charge the cache for decoded image memory. Cell reuse cancels old requests and checks the represented URL before displaying a result.
- All saved AI connections must use the exact production `/write` origin. Arbitrary providers are no longer accepted by the shipping app. Old custom-host connections must be replaced by Apple sign-in.
- Per-store UUID reset generations, deletion tombstones and write timestamps reconcile personal/learning deletion before historical reads. Read-only keyboards hide pre-reset group data locally and publish pending resets when shared writes become available. Older clipboard snapshots and legacy fallback records cannot restore clips predating a reset. Clear learned words has its own marker and does not remove clipboard entries.
- CI uses read-only repository permissions. Only a separate main-branch release job has write permission, after the build/launch job succeeds. That job consumes the tested artifact, verifies checksums, and does not check out or execute repository scripts. Third-party actions are pinned to immutable commits.
- Swift checking advances from minimal to targeted. Complete checking across all legacy UI code remains incremental work; this change does not claim a Swift 6 data-race audit.
- App Store copy now distinguishes offline typing from optional account-based online AI.

## Automated regression cases

Origin lookalikes, credentials, alternate ports/paths and query strings; oversized advertised and unadvertised 9 MB/100 MB transfers; interrupted responses; cancellation; local/group deletion; Full Access transitions; legacy fallback; stale clipboard snapshots; targeted learning deletion. Backend authentication and quota regression tests remain in the release pipeline.

## Remaining release gates

Physical iPhone testing is still required for peak extension memory, OS termination/restart, Full Access changes and actual cross-process UserDefaults propagation. A read-only extension cannot erase another process's shared data immediately: clear it from the companion app or restore Full Access to publish its pending reset. Sideload builds without App Groups cannot coordinate data deletion across isolated extension sandboxes; clear each store separately.

Apple grant revocation on account deletion remains the separate limitation documented in APPLE-SIGNIN.md. Branch protection/review enforcement and App Store Connect privacy answers are account settings and must be checked by the repository/account owner. No static review or simulator run establishes production security approval.
