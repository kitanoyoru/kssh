## What this changes

A short description of the change and the motivation.

## How I verified it

- [ ] `make build` passes
- [ ] `make test` passes
- [ ] Added/updated unit tests for new pure logic (config parsing, arg building, matching)

Manual testing (what you ran, and the result) — especially for anything touching
`ssh-add` / `gpg` / live API calls / UI animation that unit tests can't cover:

> e.g. "Switched between two keys, confirmed ~/.ssh/config rewrote only the github block and ssh-add -l updated."

## Screenshots

If this changes the UI, add a before/after screenshot of the popover.

## Notes for reviewers

Anything you're unsure about, trade-offs you made, or follow-ups left out of scope.
