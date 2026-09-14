# Collections2Folders — technical documentation

Everything beyond the quick start in the [README](../README.md): how the folder
tree is built, how export presets are found and applied, what the plugin will
not do, how to diagnose failures, and what a developer needs to know about the
Lightroom SDK traps in this code.

## Contents

- [Tested configuration](#tested-configuration)
- [How folders are created](#how-folders-are-created)
- [Export presets](#export-presets)
- [Behaviour and limitations](#behaviour-and-limitations)
- [Troubleshooting](#troubleshooting)
- [For developers](#for-developers)
- [Changelog](#changelog)

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

Existing folders are reused rather than replaced. What happens to a file that
already exists is decided by the export preset's collision handling, not by the
plugin.

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

If your preset has collision handling set to **Ask**, Lightroom will interrupt
the batch with a dialog for every filename clash. For an unattended export,
save a preset that uses **Overwrite** or **Rename** instead.

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

## Behaviour and limitations

- **Smart collections** are exported like any other collection, using whatever
  they currently match.
- **Publish collections** are not listed. Only collections under the catalog's
  collection tree appear.
- **Empty collections** are skipped and produce no folder.
- **Collection sets are not selectable.** They appear in the list only to show
  where each collection sits.
- **Two collections with the same name in the same set** write into the same
  folder, because folder names come from collection names.
- **Selection is not remembered** between runs. The dialog always opens with
  everything checked.
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
| `ExportCollection.lua` | Exports one collection via `LrExportSession` |
| `Utils.lua` | Path handling, preset discovery, `.lrtemplate` parsing |

Three SDK behaviours cost real time to diagnose and are worth knowing:

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

Errors surface through a failure handler on the task's context. If you are
debugging and see nothing at all, check the error log in the Plug-in Manager.

## Changelog

### 2.0.0

- Collections are now chosen individually with checkboxes, replacing the
  all-or-one-set choice.
- Export presets are discovered from disk and offered in a dropdown.
- Fixed preset files being loaded but never applied.
- Fixed the collection list never populating.
- The two menu items are consolidated into one.
- Added a cancellable progress dialog and a summary of what was exported.
- Added folder name sanitising for characters the file system rejects.
- Errors are reported in a dialog instead of failing silently.

### 1.0.0

- Initial release. Export one collection set, or every collection set in the
  catalog, with an optional export settings file.
