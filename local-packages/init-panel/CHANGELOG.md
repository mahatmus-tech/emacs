# Changelog

## 0.2.0 — 2026-09-10

First version worth a name. Extracted from a personal Emacs config.

- Native `outline-minor-mode` folding (Emacs 29 default state, cycling, faces)
- Notes (`;>` / `;.`) drawn at a column via `display`, zoom-safe; optional right margin
- Section rules in box-drawing characters, icon per section from its name
- Left margin: form-kind icons and a "you are here" marker on the current headings
- Note decorations: keys, `[tag]` badges, symbol links (`RET` → `describe-symbol`)
- Plain `;;` / `;` comments get quiet glyphs and the same decorations
- First argument of every top-level form in its own face; imenu "Packages"
- Folded `use-package` keyword summaries; `Section › Subsection` header line
- Flymake end-of-line text hidden while reading
- Three fold states; empty keymap on purpose
- Key detection only matches whole words (`has-agenda-view`, `SECRET`, `<style>` are not keys); `M-x cmd`, `C-x o o o`, `M-S-<up>` are
- Marker faces: `;>` accent, `;.` secondary, `;;`/`;` quiet — markers stand apart from note text
- `init-panel-normalize-buffer` strips hand-typed layout; imenu index sees through folding
- ERT test suite, Makefile (test / compile / checkdoc / lint)
- `init-panel-focus`: edit one block in an indirect buffer over the panel (child frame or window)
