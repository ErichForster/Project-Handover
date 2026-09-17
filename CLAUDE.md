# Austruss — Drafting Scope & Details

Drafting scope and project handover tool; reads Excel files (SheetJS from CDN) and stores work in localStorage.

## Structure

The whole app is a single self-contained `index.html` (HTML, CSS and
JavaScript inline). There is no build step, package manager or test suite.

## Running locally

`python -m http.server 8104 --bind 127.0.0.1`, then open
http://127.0.0.1:8104/ (configured in `.claude/launch.json`).

## Working rules

- Work on a branch, open a PR, and let the user decide when to merge.
  Never push directly to `main`.
- `index.html` is large — search for the relevant section and make focused
  edits rather than rewriting the file.
- Verify UI changes in the browser preview, including a phone-width
  layout, and check the console for errors.
- Don't change backend URLs (Google Apps Script / Supabase) or anything
  touching stored data formats in localStorage without calling it out, since
  existing users' saved data depends on them.
