# UI standards

How StartFSGUI looks and behaves. **The shared rules are in the devkit: [scripts/devkit/docs/ui-standards.md](../scripts/devkit/docs/ui-standards.md).** Read them first; this file holds only what is StartFSGUI's own, and its decision log. A UI change that makes a decision, or goes against either file, updates the right one in the same change and adds a line to the log.

`SettingsWindow.qml`, `SettingsPill.qml`, `ScrollTrack.qml`, `Field.qml`, `EntryText.qml` and the window move/resize code in `Service.qml` are copies of StartAppImage's and StartDrive's (the reference implementation), kept alike by hand.

## Where StartFSGUI differs from the shared rules

- **No manager list.** The manager is a dashboard (is the data safe, the numbers, the members), not a list of items, so it has no search box, no cursor and no per-item settings window. Its keys are `r` (look again) and `s` (settings).
- **Some settings go to the daemon, not to the plugin.** The Node page (space offered, copies) runs `startfsgui set`, which runs `startfs config`. They apply instantly like the rest, but the daemon can refuse (lowering copies waits until every file has all its copies); the refusal is shown under the setting and the control flips back on the next read of `startfs status`. *Reset to defaults* never touches them: it resets the plugin's own settings, not the cluster's.
- **The manager is taller than the shared 580.** It grows to 900 (at most the screen minus 80): the storage lines, six or more member rows with their versions and the installer's log do not fit in 580. The installer's log is one line per row, cut at the card's edge, in a box of its own, so its height never depends on how long the installer's sentences are.
- **The bar icon is on in the recommended set**, because it is where "is my data safe" shows without opening anything.

## Storage figures

The numbers under the header include, when the daemon reports them (`efficiency` of `startfs status --json`, builds after 1.0.7): the size of the files, what is left after deduplication with the ratio, and this node's disk use with its compression and its share of the replicas. They are left out until there are files, and on a daemon that does not report them. The members' rows show each member's use of what it offers once `startfs stats --json` has answered (when the window opens and on "look again", never on the 5 second poll, because it asks every member); a member that did not answer says "no answer".

## Updating a node

The manager's members are selectable rows (Up/Down or j/k, or a click) showing each node's StartFS version. The row under them updates the picked node with StartFS's own installer, over ssh (here for this node): **Update** (or `u`) asks, a second press within 3 seconds goes. The box beside it names a release (`v1.0.7`); empty means the latest. The installer's output shows under the list while it runs, and a notification says how it ended. Only one update runs at a time. This node's row warns that its mount drops while the daemon restarts, and says to update it last.

## Settings

| Page | Setting | Control | Applies with |
|---|---|---|---|
| Node | Space offered | text, under its label | `set offer` (on Enter or when the box loses focus) |
| Node | Copies | choice 1 to 5 | `set copies` |
| General | App launcher entry | switch | `setup --launcher` |
| General | Command line | switch | `setup --cli` |
| Bar | Bar icon | switch | `setup --bar-icon` |
| Window | Remember size | switch | `setup --remember-size` |
| Window | Remember position | switch | `setup --remember-position` |

## Decision log

| Date | Decision | Why |
|---|---|---|
| 2026-10-17 | The per-member storage figures are asked for when the window opens, not on the poll. | `startfs stats` queries every member at that moment; every 5 seconds would be a steady load on the whole cluster for a number that changes slowly. |
| 2026-10-17 | Updating a node is two presses, and the installer's output is shown, not hidden behind a spinner. | It restarts a daemon (for this node, the mount under the user's files); a mis-click should not do that, and a failure must be readable where it happened. |
| 2026-10-17 | Node settings live in the settings window, not on the manager. | The shared rules put settings in the settings window; the first slice had them on the manager, which made it look bare and unlike the family. |
| 2026-10-17 | The manager shows warnings, repair, unreplicated chunks, conflicts and unreachable members only when there is something to say. | `startfs status --json` carries them; an empty "all fine" section is noise. |
