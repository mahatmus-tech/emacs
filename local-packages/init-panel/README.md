# init-panel

Read a comment-outlined Emacs configuration as a panel: folded sections with
icons and rules, `;>` notes aligned in a drawn column and decorated with keys,
badges and links, a kind icon per form in the left margin, a marker on the
heading of the section you are in, a breadcrumb header, folded-package summaries. Built on the
outline machinery Emacs 29 already ships. Zero dependencies. Works in `-nw`.

```
▸  ────────────────────────────────────────────────────── Core
▸  ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ Navigation
   󰛢 (add-hook 'after-init-hook #'column-number-mode)     → show column number in modeline
    (setq-default truncate-lines t)                       → [fix]: long lines never wrap here — see `truncate-partial-width-windows'
    (use-package winner  hook bind config ⬎               → undo/redo window layout changes
   ───────────────────────────────────────────────────── Visuals
   ╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌╌ Themes
 header line:  Core › Navigation
```

## The file convention

Nothing to learn beyond two markers:

```elisp
;;; Section                            ;; level 1 (or ";;; ------- Section", both render the same)
;;;; Subsection                        ;; level 2
(setq foo t) ;> why this line exists   ;; a note — the WHY, one line
             ;. continuation           ;; a note continuation (or a sub-item inside a block)
(setq bar t) ;> [fix]: C-c w reopens `my-workspaces' after a theme change
```

- A note starts with `;>` (or `#>` in a `#`-comment language: the markers are
  built from `comment-start`). One space before it is enough; the mode draws
  the column.
- `[tag]:` at the start of a note becomes a badge. The default vocabulary:
  `fix` `bug` (warning) · `hack` `deprecated` (error) · `perf` (success) ·
  `todo` `wip` · `emacs30` (version). Anything else gets a neutral badge.
- Keys like `C-c w`, `M-x foo`, `<f5>`, `TAB` are shown in the key face.
- `` `symbol' `` links to `describe-symbol`; a bare `my-func` or `my/var`
  links too when it names a bound function, variable or face.

## Install

```elisp
;; straight
(use-package init-panel
  :straight (:host github :repo "mahatmus-tech/init-panel")
  :hook (emacs-lisp-mode . init-panel-mode)
  :bind (:map init-panel-mode-map
              ("C-c C-t" . init-panel-show-headings)     ; every heading and top-level form
              ("C-c C-s" . init-panel-fold-subsections)  ; sections + subsections
              ("C-c C-y" . init-panel-fold)))            ; sections only (the open-file state)
```

The mode map is empty on purpose; bind what you like. `TAB` / `S-TAB` on a
heading cycle it / the whole buffer — that is Emacs' own
`outline-minor-mode-cycle`.

## What it does, and the switch for each

| Feature | Option | Fallback |
|---|---|---|
| Fold to sections on open, `TAB`/`S-TAB` cycling, heading faces | always (native outline) | — |
| Notes aligned at a drawn column | `init-panel-style` `'column`, `init-panel-column` 70 | `'margin` puts them in the right margin |
| Column follows the widest visible code line | `init-panel-column-auto` nil | — |
| Section rules as `─` / `╌` | `init-panel-rule-chars` | typed dashes |
| Icon per section from its name | `init-panel-section-icons` | `◆` / `◇`, then `;;;` |
| Icon per form kind in the left margin (4 cells) | `init-panel-kind-margin`, `init-panel-kind-icons`, `init-panel-margin-cells` | none |
| "You are here" marker on the current section/subsection headings (or a bar along the section) | `init-panel-section-guide` `'marker` / `'bar` / nil, `init-panel-marker-char` | none |
| Plain `;;` / `;` comments: quiet glyph, plus the note decorations below | `init-panel-prose-comments` | as typed |
| Keys in the key face | `init-panel-highlight-keys` | plain |
| `[tag]` badges | `init-panel-tag-faces` | neutral badge |
| Symbol links (`RET` / mouse-1 → describe) | `init-panel-link-symbols` | plain |
| First argument of every form (the variable, hook, key, package) in its own face | `init-panel-highlight-targets` | plain |
| "Packages" group in imenu | `init-panel-package-index` | — |
| Folded `use-package` shows its keywords | `init-panel-fold-summary` | — |
| `Section › Subsection` header line for the section point is in | `init-panel-header-line` `'point` / `'window-start` / nil | — |
| `which-function-mode` shows the section path | always | — |
| Flymake end-of-line text hidden while reading | `init-panel-quiet-diagnostics` | — |
| Note of the form at point echoed via eldoc | `init-panel-eldoc` nil / `'always` | — |
| Line at point shown as typed | `init-panel-raw-at-point` nil | — |

Icons default to [Nerd Font](https://www.nerdfonts.com/) codepoints. Every glyph
is checked with `char-displayable-p`, so without such a font you get plain
Unicode or the literal text, never a tofu box.

## Commands

- `init-panel-mode` — the minor mode.
- `init-panel-fold` / `init-panel-fold-subsections` / `init-panel-show-headings` — the three fold states.
- `init-panel-toggle-style` — column ↔ right margin, per buffer.
- `init-panel-normalize-buffer` / `init-panel-normalize-region` — strip typed layout (heading dashes, note padding) from a file that was aligned by hand; the panel draws it anyway.
- `init-panel-describe-at-point` — what `RET` on a link runs.

## How it is built

Everything is font-lock keywords with `display` properties (rules, glyphs, the
aligned column — measured in the text's own font width, so `C-x C-+` zoom keeps
notes aligned), a handful of overlays in the left margin managed by
`jit-lock`, and the built-in hooks (`window-size-change-functions`,
`outline-view-change-hook`, `post-command-hook` for the guide). Cost is
proportional to what is on screen; a 1000-line init fontifies in ~30 ms.

## Status

0.2, extracted from a personal config. Feedback and issues welcome.
