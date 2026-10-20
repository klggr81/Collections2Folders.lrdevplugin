# Changelog

All notable changes to Collections2Folders. Version numbers follow
[Semantic Versioning](https://semver.org/); the current version is the
`VERSION` table in [Info.lua](Info.lua).

## 2.1.0 — 2026-10-20

### Added

- **Include smart collections** toggle below the collection list. When it is
  off, smart collections are greyed out, left out of the selection count and
  not exported. Their ticks are kept, so switching it back on restores them.
- Smart collections are marked `(smart)` in the list.
- **Photos to export** filter. Export every photo, or only the photos matching
  all or any of these criteria:
  - **Flag:** picked, not rejected, unflagged or rejected.
  - **Rating:** at least, exactly or at most 1 to 5 stars. Unrated photos
    count as 0 stars.
  - **Color label:** any combination of red, yellow, green, blue and purple.
- A collection with no photos left after filtering is skipped and gets no
  folder.
- Before exporting, the plugin checks every destination folder. If any already
  contain files, a dialog lists them and asks what to do: skip photos that
  already exist, overwrite them, keep both with a unique name, skip those
  collections, or move the existing files to the Recycle Bin / Trash first.
- The progress window counts photos instead of collections. It names the
  collection being exported and counts down the photos left out of the total,
  e.g. `Bacau (collection 1 of 18) - 1222 of 1245 photos left`. The
  destination check and the export share one window.
- The summary reports photos that were skipped or failed, collections skipped
  because of existing files, and collections with nothing to export. After a
  cancel it shows how many photos were done, which collection was stopped
  partway and how many were not started.

### Fixed

- **Cancel** now stops the export within a few photos, and nothing keeps
  exporting in the background. Photos are exported in batches of five and a
  cancel lets the current batch finish. It used to take effect only once the
  whole collection had been exported. Presets that rename with Image # or
  Total # still export each collection in one piece, since those numbers
  cannot be carried across batches.
- The Plug-in Manager showed version 1.0 whatever the release, because the
  version was declared under a key Lightroom does not read. It is now set in
  the `VERSION` table.

## 2.0.0

- Collections are now chosen individually with checkboxes, replacing the
  all-or-one-set choice.
- Export presets are discovered from disk and offered in a dropdown.
- Fixed preset files being loaded but never applied.
- Fixed the collection list never populating.
- The two menu items are consolidated into one.
- Added a cancellable progress dialog and a summary of what was exported.
- Added folder name sanitising for characters the file system rejects.
- Errors are reported in a dialog instead of failing silently.

## 1.0.0

- Initial release. Export one collection set, or every collection set in the
  catalog, with an optional export settings file.
