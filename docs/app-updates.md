# Application updates and About

The production build writes `dist/app-version.json` and adds release, build identity and build timestamp metadata to `dist/index.html`. The build identity covers the entry JS and stylesheet filenames, so CSS-only releases are detected too. About displays the metadata in the HTML currently open on the device; it must not mislabel a server's newer release as the installed one.

`AppUpdateNotice` runs in each authenticated workspace, including operators. It checks after entry, on focus/visibility/online/pageshow activation, on About's Check for updates action, and once a minute while visible. The version endpoint is read with no-store. A missing endpoint, invalid JSON or a failed request cannot trigger navigation.

If a newer build is available, a persistent English notice offers Update now. Automatic updates require a visible, online workspace with no protected work, no focused editor, ten seconds without interaction, and a five-second countdown. Any new interaction cancels the countdown; activity beginning during the final version request cancels navigation too. Updates recheck both deployment and safety before navigating. A session-scoped attempt record prevents repeated automatic reloads of the same release within five minutes if an intermediary serves an old page. Manual retry remains available.

Protection covers unsent observation text/photos, processing, dictation, task creation, task notes, chat drafts and sends. A general edit tracker protects other modified native form controls until reverted, reset or removed. All non-read fetch requests hold a write blocker; draft and write blockers release independently. IndexedDB observation drafts resolve only after transaction commit. The updater does not clear authentication, browser storage, queued photos or saved records, and does not reload through the activation/password setup screens. Unsaved work is protected by postponing the update, not by claiming to save arbitrary forms automatically.

An update notice has no dismiss control but does not interrupt editing. Normal releases do not block business actions or introduce an unimplemented minimum-version API policy. A future server-enforced minimum-version requirement would need a separate compatibility policy.

Before publishing, run the update tests, the existing application tests and build. Verify app-version.json points to the deployed assets, About metadata matches that manifest, and Cache-Control is no-store on the version endpoint. Keep the endpoint and index revalidation headers in netlify.toml. Increment the package release number for user-facing releases; each build also has its own automatic fingerprint.

Rollout limitation: tabs that predate this mechanism need one initial refresh. After that, the detector manages subsequent releases. A final acceptance check on a real Android/iPhone must cover switching away and returning, offline recovery, an unsent photo/message, and the next deployment.
