# Austruss — Job Handover

The drafting team's job handover form: job details, building design scope,
key dates, contacts, links, scope checklist, drawings, site map and
variations, with a locked PDF for issuing.

**Live:** https://austruss-handover.apps-578.workers.dev

## Using it

- **Sign in** with the team passcode and your name. Both are remembered on
  that computer, and your name is recorded against your saves.
- **🗂 Jobs** lists every handover. Search, open, start a new one, or delete.
- **New handovers start by picking the job from Smartsheet Project Admin.**
  Job number, project name, client, site address and city/town fill in and
  are read-only, so they always match Smartsheet. To fix one, change it in
  Project Admin; the handover picks it up next time it's opened. A field
  Project Admin leaves blank stays editable. Building Type is pre-filled
  from Sector and can be changed. For a job that isn't in Smartsheet yet,
  use **Job isn't in Smartsheet** to type the details in.
- **Saving is automatic.** A job saves about 1.5 seconds after each change;
  the top bar shows "✓ Saved" and the time. If two people edit the same job,
  the second to save is asked whose version to keep. Edits made while
  offline are recovered the next time the job is opened.
- **Save Session / Save HTML / Save Locked / Print / Export Excel** download
  a file to your computer. They don't change the database.
- **Old session files** (`.json`, or a "Save HTML" copy) go in through
  **Jobs → Import files**, **Import folder**, or by dropping them on the
  list. Importing the same file twice does nothing.

## How it fits together

| Piece | Where |
|---|---|
| The app (one file: HTML, CSS and JS) | `index.html` |
| Hosting, image upload/download, Smartsheet job list | Cloudflare Worker `austruss-handover` (`worker.js`, `wrangler.jsonc`) |
| Handover jobs | Supabase project `vrhapkrtbxcccmbnjkco`, table `public.handovers` |
| Drawings, photos and markups | Cloudflare R2 bucket `austruss-handover` |
| Job list | Smartsheet **Project Admin** (Company > Admin), read-only |
| Database setup | `supabase/migrations/` (already applied) |

The `handovers` table can't be read with the public key. Every read and
write goes through a `handover_*` database function that checks the team
passcode first, so the app ships no secrets. The Worker's one secret is the
Smartsheet API token.

Images are uploaded once, under a fingerprint of their contents, and the job
keeps a link to them. Later saves only send the form's text.

## Looking after it

**Change the team passcode.** In the Supabase dashboard, open the
austruss-online-viewer project → SQL Editor, run this, and click Run:

```sql
select private.handover_set_passcode('the new passcode');
```

It takes effect immediately. Everyone is asked for the new one on their next
save or open, without losing what they were doing.

**Replace the Smartsheet token.** Generate one in Smartsheet → Apps &
Integrations → API Access (the account needs access to Project Admin), then
paste it when asked:

```powershell
cd C:\Users\erich.forster\Code\Project-Handover; npx wrangler secret put SMARTSHEET_TOKEN
```

**Undo a delete.** Deletes only hide the job. In the Supabase SQL Editor:

```sql
update public.handovers set deleted_at = null where job_number = '25177';
```

**Deploy** from `main`, after merging. The first time on a computer, run
`npx wrangler login` first.

```powershell
cd C:\Users\erich.forster\Code\Project-Handover; git checkout main; git pull; npx wrangler deploy
```

## Working on it

Run it locally through the Worker, so image upload and the Smartsheet list
work. Use the `project-handover` preview in Claude Code, or:

```powershell
cd C:\Users\erich.forster\Code\Project-Handover; npx wrangler dev --persist-to ../.wrangler/project-handover-state --port 8104
```

Then open http://127.0.0.1:8104/. The local copy uses the **real** shared
database, so delete any test jobs you create. Images go to a local stand-in
for R2. The Smartsheet list needs the token in a `.dev.vars` file
(`SMARTSHEET_TOKEN=...`), which must never be committed.

Work on a branch and open a pull request. `CLAUDE.md` has the code-level
notes.
