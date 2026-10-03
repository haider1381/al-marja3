# Install Medbrain

Medbrain is now an installable Progressive Web App (PWA), served at https://haider1381.github.io/al-marja3/. It uses the same library, study planner, account permissions and AI service. No native store binary, App Store submission, Google Play submission or store developer account is part of this release.

## Student instructions

- iPhone / iPad: open the link in Safari, choose Share → Add to Home Screen → Add. Enable Open as Web App if the device shows that option. Launch the Medbrain brain icon from the home screen.
- Android: open the link in Chrome and choose Install Medbrain at login or in Settings. If a native browser install prompt is unavailable, open the Chrome ⋮ menu and choose Install app / Add to Home screen. Menu wording varies by version/device.
- Desktop: use Install Medbrain in Settings or the browser's address-bar install button.
- A link inside a messaging app may need to be opened in Safari/Chrome first. The app can then be installed normally.
- In standalone app windows the installation controls are disabled and indicate that the app is already open independently. Browser tabs cannot reliably determine installation on every platform; the UI does not falsely claim universal detection.

The installation guide is available before signing in and from Settings. Android/desktop browsers that emit `beforeinstallprompt` get a real, user-triggered install prompt; unsupported browsers receive platform instructions. The app uses manifest standalone display, Arabic RTL metadata, 192/512 PNG icons, a safe-area maskable icon and a 180 PNG apple-touch-icon rasterized from the site's existing brain vector.

## Network, updates and privacy

The manifest ID, start URL and scope are relative `./`, resolving to `/al-marja3/`. Worker registration also uses this project scope. It never claims the origin root or sibling GitHub Pages projects. Start URL has no tracking query and retains the existing auth routing.

The worker caches only the public offline page and four installation icons. It never caches the app's index.html or arbitrary runtime requests. GET navigations fetch the live page with revalidation; a failed network navigation receives the generic offline screen. Current work in an open tab is never automatically reloaded or interrupted by an update. A newly installed worker waits until old app windows close before activating, and only deletes its own `medbrain-pwa-` caches. Reopen/reload online to receive current site changes; external CDN HTTP caching remains managed by the browser/CDN.

Cross-origin requests, non-GET requests, private API traffic, signed PDF URLs, auth flows and AI responses are not intercepted or stored in worker caches. The library, schedule, login and AI still require connectivity. The offline screen explicitly says so; this release does not promise offline lecture downloads. Existing Supabase session storage behavior is unchanged; installation is not an additional offline copy of account data. Installed-app browser storage/session behavior varies by OS; students may need to sign in again after installation. Google/password authentication and recovery URLs have not been modified.

`theme-color` is supplied for OS light/dark modes, plus Apple standalone metadata. Existing site safe-area CSS handles screen insets. No native notifications, background sync, native purchases or App Store/Google Play listing is enabled.

## Validation

Run `node tests/pwa.test.cjs` at repository root. It checks manifest/project scope, icon PNG dimensions, public cache allowlist, private API/PDF bypass, fresh navigations, network-failure fallback and cleanup isolation from other sites.

Chromium browser tests ran against a local HTTP project path with a real service worker at 390/768/1440px in light/dark themes. Verified manifest parsing, worker scope/controller, public cache keys, manual instructions, simulated beforeinstallprompt acceptance, installed-state UI, real offline navigation and reconnection, and no runtime/horizontal-layout errors. iPhone instructions were tested using an iPhone user agent; physical iOS/Safari installation and native store review were not performed. Existing-site regressions covered navigation/profile, favorites/errors, schedule, sharing/privacy, reader and settings. Network sign-in was not performed on behalf of a student. GitHub Pages deployment and public manifest/icon/worker URLs were verified after publication.