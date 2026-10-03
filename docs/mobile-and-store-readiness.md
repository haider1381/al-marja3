# Device improvements and store preparation — 2026-10-03

## Delivered

- 44px touch targets, 16px mobile form text, safe-area handling, portrait/landscape adaptations and a five-item thumb navigation bar for home/library/schedule/favorites/settings.
- A focus/rest timer available from login, reading and settings. Configurable work/rest/cycles, minimize-to-floating status, pause/resume, manual next period, no trailing rest, wall-clock timing across background/foreground. Timer is independent of lecture-completion checkboxes and sends no usage data to a backend. Full app termination clears it.
- Account-only export, explicit deletion confirmation, public privacy/support and web deletion pages. Web deletion route preserves an intent through login and opens settings; no automatic deletion follows login.
- A JWT-required `delete-my-account` Edge Function, enabled on Supabase. It verifies the user server-side, requires a real active session and sign-in within 10 minutes, refuses caller-chosen target IDs, revokes sessions, removes only verified own avatar objects through Storage API, deletes the Auth user (personal tables have ON DELETE CASCADE), and clears user AI quota counters. Shared library data and global counters remain. Administrative owners and owners of shared/unknown files must transfer responsibility before deletion; no library attachment is silently removed.
- Two narrow SECURITY INVOKER RPCs in `supabase/account-deletion.sql`, executable only by service_role; no public/RLS widening. Service key lives only in the function environment. No existing user was deleted during implementation/testing.
- A pinned Capacitor project and reproducible Android/iOS preparation with embedded local UI/client/assets, native share/export, haptics, back handling, browser/PDF opening, optional generic focus notifications, brain icons and privacy manifest preparation. Native Google defaults disabled until external PKCE callbacks are configured; website Google remains working. No remote-server wrapper configuration.

## Store requirements verified against current official sources

Apple review guideline 4.2 requires value beyond a repackaged website; device utilities and native behavior improve that case but cannot guarantee acceptance. Guideline 4.8 and privacy/account deletion requirements must be reviewed for the final login model and archive. Google requires account deletion within the app and a functional outside-app web resource, plus accurate Data safety declarations.

Sources reviewed: https://developer.apple.com/app-store/review/guidelines/ and https://support.google.com/googleplay/android-developer/answer/13327111 . Device/signing requirements vary over time; check the current SDK/store console requirements before submission.

## Validation and limits

- Browser tests: 320/390px phones, 768px tablet, 1024px tablet landscape, 1440px desktop and 844×390 phone landscape, light/dark. Checked thumb navigation, focus timing/pause/rest/minimize, account-only export, deletion refusal/confirmation, reader modal/back handling, no duplicate IDs, no horizontal overflow or runtime errors.
- Existing PWA tests still pass: real service worker, scope, manifest/icons, install guidance, offline fallback/reconnect. Existing navigation/profile/favorites/share/schedule/reader/settings regressions pass.
- `tests/device.test.cjs` verifies timing/phase math and background deadlines. `tests/deletion.test.cjs` verifies forged targets, missing/old/revoked auth, origin rejection, owner/shared-file guards, avatar path checks and delete failure/order with mocked dependencies. Live unauthenticated deletion requests return 401. Real SQL confirms student/anon cannot execute server-only deletion RPCs. No test destroys an existing student account.
- Native bundle build, Android/iOS project generation/sync, icon/manifest preparation and dependency audit complete. Physical Android/iPhone/iPad behavior, true OS notification timing, camera/photo picker, full OAuth/recovery, real deletion of a disposable review account, VoiceOver/TalkBack and signed release builds still require device testing. The environment has Java 21 but no configured Android SDK or Xcode; no APK/AAB/IPA has been signed or submitted.
- `npm audit --omit=dev` reported 0 vulnerabilities for installed native dependencies at validation time.

## Remaining owner/release work

1. Supply owner-approved support email and developer accounts; replace the current project-profile/issue support route with that direct contact. Never put secrets in repository files.
2. Confirm final bundle ID and content redistribution rights. The library contains third-party lecture material, so store rights cannot be inferred merely from access to the files.
3. Configure and device-test native external PKCE login. For iOS third-party Google login, implement/provision the equivalent Apple-compliant option and Apple-token revocation on account deletion; do not mark the capability configured merely by changing a flag.
4. Test a disposable ordinary account deletion (and its avatar) on staging/controlled review data; retain owner/editor accounts and library files.
5. Review retention/backups and all provider privacy practices; complete Apple labels and Google Data safety/medical-education declarations accurately. The published policy describes verified collection and does not invent a backup-retention deadline.
6. Build on proper SDKs, run accessibility/keyboard/notch/tablet/background tests, create store screenshots and a working review account, configure signing, and run the release preflight before TestFlight/Play testing and review.

These are release dependencies, not ordinary confirmation requests. The delivered website/device improvements are usable now; store acceptance and signed binaries remain unverified.