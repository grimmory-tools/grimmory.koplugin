# grimmory.koplugin

> [!WARNING]
> This is ALPHA software and WILL have bugs or other inadvertent behaviors.
> 
> Beware, that makes you an ALPHA tester.  This software may require you to
> erase data on your device, or on your Grimmory server.
>
> Please report any bugs or issues.

Read your books from Grimmory, sync your shelves, and track reading
progress automatically.

**Sync Book Read Status** is enabled by default. During synchronization, Grimmory
statuses map to KOReader statuses as follows:

| Grimmory | KOReader |
| --- | --- |
| Read (`READ`) | Finished |
| Reading (`READING`), Re-reading (`RE_READING`) | Reading |
| Paused (`PAUSED`), Abandoned (`ABANDONED`) | On hold |
| Unread (`UNREAD`), Unset (`UNSET`) | New, clearing the saved reading position |

Partially Read, Won't Read, missing, and unknown statuses leave
KOReader's status unchanged. The mappings apply to newly downloaded books and
existing associated books even when downloads or reading progress sync are
disabled. Ratings, notes, annotations, and reading history are preserved. Only
Unread and Unset clear the saved position; the other mappings preserve it.
Status sync does not send KOReader statuses back to Grimmory.

Unread and Unset reset a book once when first observed or when its observed
Grimmory status changes into either state. The open book moves to its beginning.
Older local and remote progress, including progress dated in the reset's second,
cannot restore the previous position. New reading after that boundary uploads
normally and can change Grimmory back to Reading. Repeated syncs of the same
Unread or Unset state preserve this new reading. Grimmory does not expose a
status revision, so a second reset to the same state can only be detected after
the plugin has observed an intervening status. Progress protection uses device
and server timestamps; their clocks should agree.

While this option is enabled, pending reading progress is checked against
Grimmory before upload. Progress for Read, Re-reading, Paused, and Abandoned books
is retained without uploading because the progress endpoint would overwrite
those statuses. Reading books still upload progress normally, including when
they reach completion. If the status cannot be retrieved or the local file has
been replaced, progress waits for a later sync; reading sessions can still upload.
Disable **Sync Book Read Status** to restore the usual progress upload behavior.

## Installation

Download the [latest release][latest-plugin] file and extract it to
your KOReader plugin folder.  Then, restart KOReader.

The Grimmory plugin is under "Tools" (🛠️) for configuration.

## Updating

Updating can either be done manually by replacing the plugin folder
in KOReader with the [latest release][latest-plugin] or by using the
built-in updater.

The updater may be found at:

**Tools** -> **Grimmory** -> **About Grimmory Sync**

From that menu you may **Check for Updates** and update the plugin
to the latest release.

> [!TIP]
> You must restart KOReader to see the updates apply.

## License

Distributed under the terms of the [AGPL-3.0 License](./LICENSE).

[latest-plugin]: https://github.com/grimmory-tools/grimmory.koplugin/releases/latest/download/grimmory.koplugin.zip
