# Collections2Folders — technical documentation

Everything beyond the quick start in the [README](../README.md): how the folder
tree is built, how export presets are found and applied, what the plugin will
not do, how to diagnose failures, and what a developer needs to know about the
Lightroom SDK traps in this code.

## Contents

- [Tested configuration](#tested-configuration)
- [How folders are created](#how-folders-are-created)
- [Export presets](#export-presets)
- [Choosing which photos are exported](#choosing-which-photos-are-exported)
- [Files that already exist](#files-that-already-exist)
- [Cancelling an export](#cancelling-an-export)
- [Behaviour and limitations](#behaviour-and-limitations)
- [Troubleshooting](#troubleshooting)
- [For developers](#for-developers)

## Tested configuration

| | |
| --- | --- |
| Lightroom Classic | **15.5.1 [ 202608131348-cab7eed5 ]** |
| Operating system | Windows 11 |
| Declared SDK version | `LrSdkVersion = 13.0`, `LrSdkMinimumVersion = 13.0` |

That single build is the only configuration the plugin has actually been run
on. Lightroom Classic 13 and newer should work, since nothing here uses an API
added after SDK 13, and macOS paths are handled explicitly in the preset
scanner — but neither has been verified. If you run it elsewhere, successfully
or not, that is worth reporting.

## How folders are created

Each selected collection gets a folder whose path mirrors its position in the
catalog. Given this catalog:

```
Travel                 (collection set)
  Japan 2024           (collection set)
    Tokyo              (collection)
    Kyoto              (collection)
Portraits              (collection)
```

exporting everything to `D:\Export` produces:

```
D:\Export\Travel\Japan 2024\Tokyo\
D:\Export\Travel\Japan 2024\Kyoto\
D:\Export\Portraits\
```

Folder names come from the collection and set names, with characters that
Windows and macOS reject replaced by a hyphen. That covers `/ \ : * ? " < > |`.
Leading and trailing whitespace and trailing dots are stripped, and a name that
ends up empty becomes `Untitled`.

Existing folders are reused rather than replaced. What happens to files that
are already in them is covered under
[Files that already exist](#files-that-already-exist).

## Export presets

The dropdown is populated by scanning Lightroom's preset folders on disk. The
SDK exposes no API for reading a user's export presets, so the plugin reads the
`.lrtemplate` files directly. It looks in:

| Platform | Location |
| --- | --- |
| Windows | `%APPDATA%\Adobe\Lightroom\Export Presets` |
| macOS | `~/Library/Application Support/Adobe/Lightroom/Export Presets` |
| Either | `<catalog folder>\Lightroom Settings\Export Presets` |

The third covers the **Store presets with this catalog** option. Each folder is
scanned recursively, so both `User Presets` and the built-in presets are found,
and each entry is labelled with the folder it came from. Presets are read fresh
every time the dialog opens, so a preset you save in Lightroom shows up the next
time you run the plugin.

Use **Other file** to load a `.lrtemplate` from anywhere else. It is added to
the dropdown and selected.

### Keys the plugin overrides

Whatever the preset says, these are replaced so the photos land in the folder
tree rather than wherever the preset last pointed:

- `LR_export_destinationType`
- `LR_export_destinationPathPrefix`
- `LR_export_destinationPathSuffix`
- `LR_export_useSubfolder`
- `LR_export_useParentFolder`

Everything else in the preset is used as written: format, quality, colour
space, sizing, sharpening, metadata handling, watermarking, file renaming. Your
`.lrtemplate` files are never modified.

If a preset does not name an export service, the plugin targets the hard drive.

### A caveat about collision handling

When the plugin finds existing files at the destination, the choice you make
in its dialog replaces the preset's collision handling (see
[Files that already exist](#files-that-already-exist)). Otherwise the preset's
setting applies. If that is **Ask**, Lightroom can still interrupt the batch
when two photos in one collection end up with the same file name. For an
unattended export, save a preset that uses **Overwrite** or **Rename**.

### Writing a preset by hand

A `.lrtemplate` file is a Lua chunk assigning a table named `s`. See
[`assets/SampleExportSettings.lrtemplate`](../assets/SampleExportSettings.lrtemplate):

```lua
s = {
  id = "40A740D2-FA5C-4507-8FD0-789893B413FE",
  internalName = "Sample",
  title = "Sample",
  type = "Export",
  value = {
    LR_format = "JPEG",
    LR_jpeg_quality = 1,
    LR_export_colorSpace = "AdobeRGB",
    LR_size_resolution = 300,
    LR_size_doConstrain = false,
    LR_size_doNotEnlarge = true,
    LR_metadata_keywordOptions = "lightroomHierarchical",
    LR_removeLocationMetadata = false,
    LR_reimportExportedPhoto = false,
    LR_collisionHandling = "overwrite",
    LR_initialSequenceNumber = 1,
    LR_renamingTokensOn = true,
    LR_tokens = "{{date_YY}}{{date_MM}}{{date_DD}}_{{naming_sequenceNumber_3Digits}}",
  },
  version = 0,
}
```

The `title` field is what the dropdown shows. If it is missing, the filename is
used instead.

Note the prefix difference. Presets that Lightroom itself saves store their keys
**without** the `LR_` prefix, while the SDK's export API requires it. The plugin
adds the prefix when it is missing and leaves it alone when it is already there,
so hand-written files in either style work.

For the full list of valid keys, see *Lightroom Classic built-in property keys*
in the [Lightroom Classic SDK Guide](https://d1g4ig3mxc5xed.cloudfront.net/static/installers/lr/sdk/2020/doc/Lightroom%20Classic%20SDK%20Guide%202020.pdf).

## Choosing which photos are exported

### Smart collections

Smart collections are listed with `(smart)` after their name and exported like
any other collection, using whatever they match at the moment of export.

Untick **Include smart collections** to leave them out. They are greyed out,
the selection count drops them, and nothing from them is exported. Their
checkboxes keep their state, so ticking the option again restores the earlier
selection.

### Filtering by flag, rating and colour label

The **Photos to export** box decides which photos inside each selected
collection are written. **All photos** exports everything. **Only photos
matching** applies the criteria you tick:

| Criterion | Options |
| --- | --- |
| Flag | Picked, Not rejected, Unflagged, Rejected |
| Rating | at least / exactly / at most, 1 to 5 stars |
| Color label | any combination of Red, Yellow, Green, Blue, Purple |

The **all of / any of** menu sets how ticked criteria combine. With *all of*, a
photo must pass every ticked criterion — for example, picked **and** at least
3 stars. With *any of*, passing one is enough. Within the colour criterion,
the ticked colours are always alternatives: ticking Red and Green matches a
photo labelled either.

Unrated photos count as 0 stars, so *at most 2 stars* includes them. Photos
with a custom label outside the five standard colours never match the colour
criterion.

The filter applies to every selected collection alike. A collection with no
photos left after filtering is skipped and gets no folder. Choosing **Only
photos matching** without ticking any criterion, or ticking Color label
without a colour, stops the export with a message rather than guessing.

## Files that already exist

After you click **Export**, and before anything is written, the plugin works
out every collection's destination folder and looks inside it. The progress
window shows this check before it moves on to the export; cancelling during
the check stops without writing anything.

If any folder already contains files, a dialog lists those folders with their
file counts and asks what to do:

| Choice | Effect |
| --- | --- |
| Skip photos whose file already exists | Lightroom's collision handling **Skip**. Good for resuming an interrupted export. |
| Overwrite files that already exist | Collision handling **Overwrite**. |
| Keep both | Collision handling **Rename**: new files get a numeric suffix. |
| Skip collections whose folder already contains files | Those collections are left out entirely; the rest export with the preset's own collision handling. |
| Move the existing files to the Recycle Bin first | The files are moved to the Recycle Bin (Trash on macOS) and then the export runs into the emptied folders. |

The default is to skip existing photos. Cancel in that dialog stops without
writing anything.

Some details:

- Only files **directly inside** a collection's folder count, and only those
  are moved to the Recycle Bin. Subfolders are left alone, because a
  collection set with the same name as a collection shares its folder.
- Files the operating system creates on its own (`Thumbs.db`, `desktop.ini`,
  and names starting with a dot such as `.DS_Store`) are ignored.
- The plugin cannot predict output file names, since they depend on the
  preset's renaming and format. Skip and overwrite therefore act on whatever
  file name Lightroom produces. A photo is only treated as already exported if
  the preset names it the same way as last time.
- If any file cannot be moved to the Recycle Bin, nothing is exported. Network
  drives often have no Recycle Bin, so this choice may not work there.
- Empty folders that already exist are not reported; they are simply reused.

## Cancelling an export

The progress window names the collection being exported and counts down the
photos left out of the total, for example
`Bacau (collection 1 of 18) - 1222 of 1245 photos left`.

Photos are handed to Lightroom in batches of five, each its own export. Once
a batch has started Lightroom finishes it no matter what, so **Cancel** waits
for the current batch — the caption switches to *Canceling* — and then stops.
Nothing carries on in the background, and the summary reports exactly how far
the export got. To finish later, run it again and choose **Skip photos whose
file already exists**.

Each batch briefly appears in Lightroom's activity viewer (top left).
Cancelling one there with the X skips only that batch; use the plugin's
Cancel button to stop the whole run.

Batching has two consequences for file renaming:

- **Sequence #** carries on from batch to batch, so numbering runs through the
  whole collection exactly as before. As before, it restarts for each
  collection.
- **Image #** and **Total #** count within a single export and cannot be
  carried over. If the preset renames with either, each collection is exported
  in one piece instead, and Cancel then takes effect only after the collection
  being exported.

## Behaviour and limitations

- **Smart collections** are included by default. See
  [Smart collections](#smart-collections).
- **Publish collections** are not listed. Only collections under the catalog's
  collection tree appear.
- **Empty collections**, including those emptied by the photo filter, are
  skipped and produce no folder.
- **Collection sets are not selectable.** They appear in the list only to show
  where each collection sits.
- **Two collections with the same name in the same set** write into the same
  folder, because folder names come from collection names.
- **Selection is not remembered** between runs. The dialog always opens with
  everything checked, smart collections included and the photo filter off.
- **Virtual copies** are exported, since they are photos in the collection.
- Large catalogs take a few seconds to enumerate before the dialog appears.

## Troubleshooting

**"No script by the name ..." when you pick the menu item.** Lightroom is
pointed at a path where the plugin no longer is. This happens if you move or
rename the plugin folder after installing it. Remove the entry in the Plug-in
Manager and add the plugin again from its current location.

**The menu item does nothing and no window opens.** Check **File > Plug-in
Manager**, select the plugin, and read the error log at the bottom of the panel.
From version 2.0 the plugin reports failures in a dialog rather than dying
silently, so this should be rare.

**The dropdown shows only "Lightroom defaults".** No `.lrtemplate` files were
found. Save an export preset from Lightroom's export dialog, or point the plugin
at a file with **Other file**.

**The export ignored my preset.** Versions before 2.0 loaded preset files but
never applied them, because of the `LR_` prefix mismatch described above.
Upgrade.

**Lightroom asks about overwriting on every photo.** Your preset uses **Ask**
for collision handling. See the caveat above.

## For developers

The Lightroom SDK documentation is thin, so here is the map and the traps.

| File | Role |
| --- | --- |
| `Info.lua` | Plugin manifest and menu registration |
| `ExportAllCollectionSetsGUI.lua` | Menu entry point |
| `ExportDialog.lua` | Builds the dialog and drives the export run |
| `CollectionTree.lua` | Flattens the catalog hierarchy into display order |
| `ExportCollection.lua` | Plans the jobs and exports one collection via `LrExportSession` |
| `ConflictDialog.lua` | Asks what to do about files already at the destination |
| `PhotoFilter.lua` | Flag, rating and colour label filtering |
| `Utils.lua` | Path handling, preset discovery, `.lrtemplate` parsing |

Five SDK behaviours cost real time to diagnose and are worth knowing:

**Function contexts die when the call returns.** Building a dialog inside
`LrFunctionContext.callWithContext` while fetching the catalog data from a task
started within it does not work. The context, and the property table your
bindings depend on, is torn down as soon as the outer call returns, so the
dialog has nothing live to bind to. Use
`LrFunctionContext.postAsyncTaskWithContext`, which keeps the context alive for
the life of the task.

**You cannot yield across a C call.** Catalog reads such as `getName()` yield.
Lua 5.1 cannot yield out of a C function, so calling one inside a `table.sort`
comparator, inside `pcall`, or inside a view's button handler raises
*"Yielding is not allowed within a C or metamethod call"*. Read the values you
need into plain Lua variables first and sort on those, use `LrTasks.pcall`
instead of `pcall`, and wrap button handlers in `LrTasks.startAsyncTask`.

**Preset files and the export API disagree about key names.** `.lrtemplate`
files written by Lightroom omit the `LR_` prefix that `LrExportSession` expects.
Passing the table through untranslated fails silently, leaving every setting at
its default.

**`doExportOnCurrentTask` cannot be interrupted.** It returns only when the
whole batch is done, so a cancel flag checked around it takes effect one
collection late. Iterating `session:renditions()` does not help either:
Lightroom queues every photo for rendering as soon as iteration starts,
`skipRender()` then raises *"must not be called after exportSession has
started rendering"*, and leaving the loop lets the queued renders finish in the
background. Cancelling a progress scope passed to
`renditions { progressScope = ..., stopIfCanceled = true }` ends the loop but
not the rendering. The only reliable stop is not to start: the plugin exports
in sessions of `CHUNK_SIZE` photos and checks for a cancel between them,
carrying `LR_initialSequenceNumber` across sessions so sequence numbers keep
counting.

**A modal progress dialog closes only when its function context ends.**
Calling `done()` leaves it on screen showing *Task completed*, even when it was
created in a nested `callWithContext`. Use one progress dialog for the whole
run, and show the closing summary from a new task so the old one can end and
take the dialog with it.

Errors surface through a failure handler on the task's context. If you are
debugging and see nothing at all, check the error log in the Plug-in Manager.

Version history is in [CHANGELOG.md](../CHANGELOG.md).
