# Release notes

The generator (`release-notes.sh`, from shipyard) writes the notes file for every release: the title,
a "What changed" section, a "Build ingredients" section when a pin moved, and the footer. That one
file, `dist/RELEASE_NOTES.md`, becomes both the GitHub Release body and the Sparkle appcast
`<description>`: the same bytes, read twice.

WezTerm publishes no notes for the snapshots of `main` this repo builds, so a release that ships a new
upstream links the history leading up to the pinned commit:
`build/upstream-release-notes-url.sh <upstream-version>` prints
`https://github.com/wezterm/wezterm/commits/<DIGEST>`, reading `DIGEST` from
`components/wezterm/version`, and refuses a version that is not that pin's `COMMITTED`.

A file here, named `<full-version>.md` (e.g. `20261026.072628-mavericks.1.md`), is OPTIONAL
hand-written prose for that one release, inserted verbatim right after the generated title. It must
NOT start with its own `## ` heading: the generator already emits the title, and a second one would
double it.

Prose here publishes only once a human has edited it and added the line `<!-- edited by a human -->`;
until then `release-notes.sh` refuses the release. The generator strips that line from what it
publishes. Whoever changes marked prose removes the line in the same commit, so a human reads it again.

Most releases have no file here, and that's fine: the generator's own sections are the whole note.
