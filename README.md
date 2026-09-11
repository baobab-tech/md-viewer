# Markdown Viewer

A native macOS reader for Markdown files. Opens `.md` from Finder, renders it, keeps
up with files that other tools are writing, and gets out of the way.

Built as a single Swift file against SwiftUI, WebKit and [marked](https://marked.js.org).
No Xcode project, no dependencies to resolve — `./build.sh` produces the app.

## Install

Download `Markdown Viewer.dmg` from [Releases](https://github.com/baobab-tech/md-viewer/releases),
open it, drag the app onto Applications.

The build is ad-hoc signed, not notarized, so the first launch needs a right-click on
the app ▸ **Open** ▸ **Open**. Afterwards it launches normally.

To make it the default for Markdown: right-click any `.md` file in Finder ▸ **Get Info**
▸ **Open with** ▸ Markdown Viewer ▸ **Change All…**

Requires macOS 13 or later. Universal binary (Apple silicon and Intel).

## What it does

- Renders GitHub-flavoured Markdown: tables, task lists, fenced code, footnotes.
- Lists the document's headings in a sidebar; click one to scroll to it.
- Edits in place — ⌘⇧P swaps between the rendered view and a plain-text editor.
- Reloads from disk on ⌘R, and on its own when another program writes the file.
- Exports the rendered page to PDF with a print stylesheet, so dark mode doesn't
  produce grey-on-white output.
- Copies the raw Markdown back to the clipboard.
- Follows the system appearance, or pins itself to light or dark.

| Shortcut | Action |
| --- | --- |
| ⌘⇧P | Toggle edit / preview |
| ⌘R | Reload from disk |
| ⌘S | Save |
| ⌘N | New document |
| ⌘O | Open |

## Files another program is writing

Point it at a file that a coding agent, a build script or another editor is rewriting
and the window follows along: the change is picked up within a couple of seconds and
the scroll position is kept, so the page doesn't jump to the top each time.

A window that is only being read never writes to the file. macOS autosaves documents
in place, with no switch to turn that off, so the app clears the document's edited
flag after every reload it performs itself — autosave has nothing to write, and the
"file has been changed by another application" dialog doesn't appear. Text typed in
the editor is exempt: unsaved edits suppress the automatic reload and keep the normal
macOS conflict prompt.

## Build from source

```bash
git clone https://github.com/baobab-tech/md-viewer.git
cd md-viewer
./build.sh                 # -> build/Markdown Viewer.app
./package.sh               # -> build/Markdown Viewer.dmg
```

`build.sh` fetches `marked.min.js` and generates the icon on first run, compiles
`Sources/main.swift` for arm64 and x86_64, assembles the bundle, signs it ad-hoc and
re-registers it with Launch Services.

## Layout

| Path | Contents |
| --- | --- |
| `Sources/main.swift` | The whole app: document, outline parser, web view, toolbar |
| `Resources/template.html` | Page shell, marked configuration, theme CSS |
| `Tools/` | Icon and DMG-background generators, run by the build scripts |
| `Info.plist` | Bundle metadata and the Markdown document type |
| `build.sh`, `package.sh` | Build the app; wrap it in a DMG |

Rendering is done by marked, vendored at build time under its MIT licence.
