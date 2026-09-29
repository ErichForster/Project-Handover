# Austruss — Drafting Scope & Details

Drafting scope and project handover tool. Handover jobs are stored in
Supabase behind a shared team passcode; images go to Cloudflare R2.

## Structure

- `index.html` — the whole app (HTML, CSS and JavaScript inline). No build
  step, package manager or test suite. The database code is the
  "DATABASE (Supabase + R2 images via the Worker)" section near the end.
- `worker.js` + `wrangler.jsonc` — Cloudflare Worker `austruss-handover`:
  serves `index.html` and the image endpoints (`PUT /api/images/<sha256>.<ext>`,
  `GET /images/<sha256>.<ext>`) backed by the R2 bucket `austruss-handover`.
- `supabase/migrations/` — the `handovers` table and `handover_*` functions,
  applied to the shared project `vrhapkrtbxcccmbnjkco`.

## Job details from Smartsheet

- Every handover starts by picking its job from Smartsheet **Project Admin**
  (sheet `2922076222476164`, Company > Admin), where job numbers are issued.
  `GET /api/projects` in `worker.js` reads 11 columns (by column id) with the
  `SMARTSHEET_TOKEN` Worker secret, drops quotes/lost bids, overhead codes
  (region `AUSTRUSS`, sector `(Internal)`) and duplicates, and strips the
  `.0` Smartsheet puts on numbers. Job numbers can carry letters (`22095A`).
- Job number, project name, client, site address and city/town are then
  read-only (`state.ssLinked`, `state.ssFields`). A field the sheet leaves
  blank stays editable. Building Type is pre-filled from Sector, editable.
- "Job isn't in Smartsheet" sets `state.ssLinked = 'unlisted'` and unlocks
  everything. Older handovers (no `ssLinked`) keep their values until someone
  picks the job.
- The "Project & Zone" sheet was considered and rejected: it has no address.

## Data model

- `public.handovers` holds one row per job; `data` is the app's whole `state`
  object with base64 images replaced by `/images/...` URLs.
- The table is closed to the publishable key. Every read/write is a
  `handover_*` function that checks the passcode (bcrypt hash in
  `private.handover_settings`). Change it in the Supabase SQL editor:
  `select private.handover_set_passcode('…');`
- Saves carry the version the editor loaded; a mismatch is a 409 and the app
  asks whose version to keep. Deletes are soft (`deleted_at`).
- Imports dedupe on the SHA-256 of the file (`import_hash`).

## Running locally

Use the `project-handover` preview config (`wrangler dev` on port 8104) — plain
`python -m http.server` can't serve the image endpoints. The local R2 bucket is
simulated; Supabase is the real shared database, so clean up test rows.

## Working rules

- Work on a branch, open a PR, and let the user decide when to merge.
  Never push directly to `main`.
- `index.html` is large — search for the relevant section and make focused
  edits rather than rewriting the file.
- Verify UI changes in the browser preview, including a phone-width
  layout, and check the console for errors.
- Code that fills the form (not a person typing) must run inside
  `formLoading++ … formLoading--`, or `autoSave()` fires mid-load and
  overwrites the local autosave with a half-filled form.
- Don't change backend URLs (Supabase / R2) or the shape of `state` and the
  localStorage keys (`austruss_autosave`, `austruss_cloud_job`,
  `austruss_passcode`, `austruss_editor`) without calling it out, since saved
  jobs and people's browsers depend on them.
