# UI standards

How StartFSGUI looks and behaves. **The shared rules are in the devkit: [scripts/devkit/docs/ui-standards.md](../scripts/devkit/docs/ui-standards.md).** Read them first; this file holds only what is StartFSGUI's own, and its decision log. A UI change that makes a decision, or goes against either file, updates the right one in the same change and adds a line to the log.

`SettingsWindow.qml`, `SettingsPill.qml`, `ScrollTrack.qml`, `Field.qml`, `EntryText.qml`, `Switch.qml` and the window move/resize code in `Service.qml` are copies of StartAppImage's and StartDrive's (the reference implementation), kept alike by hand. `SettingsWindow.qml` is StartDrive's copy (with its `action` fields, `titleGlyph`, `initialPage` and `Switch.qml`) plus two additions that belong upstream: an `info` field type (a read-only value on the right, or under the label when `stacked`, with `tone` bad, ok or muted; the search matches its text too) and a glyph slot sized to the glyph, because icon-font glyphs draw wider than they advance.

## Where StartFSGUI differs from the shared rules

- **The manager is a list of nodes**, modelled on StartAppImage's: each node is like an app. It has a header, a health banner, a search box, rows grouped by site and a footer ([The manager](#the-manager)). A node has its own window ([Node window](#node-window)). The gear opens the StartFS window, the app's settings window.
- **Settings go to the daemon, not to the plugin.** Space offered, weight, site and copies run `startfsgui set`, which runs `startfs config` (for another node, over ssh). They apply instantly like the rest, but the daemon can refuse (lowering copies waits until every file has all its copies); the refusal is shown under the setting and the control flips back on the next read of `startfs status`. *Reset to defaults* never touches them: it resets the plugin's own settings, not the cluster's.
- **The manager is taller than the shared 580.** It grows to 900 (at most the screen minus 80): the health banner with its attention lines and six or more node rows do not fit in 580.
- **The bar icon is on in the recommended set**, because it is where "is my data safe" shows without opening anything.
- **Red means lost.** Only down, lost and failed are red. Unknown (the daemon just restarted) and upgrading are neutral. Status dots are neutral when healthy; accent is for an upgrade step that is happening (staging, restarting) and for the one action to take.

## The manager

- **Header.** The icon, "StartFS" and a small-caps line: `FS NAME · N NODES · RELEASE`. An accent **Upgrade to vX** button shows when GitHub has a newer stable release than most nodes run (the CLI caches `latest` for 6 hours). Then the gear and look again.
- **Health banner.** A shield or warning glyph, a headline, one summary line, up to three attention lines and then "and N more". While members have upgrade steps it adds a cluster-upgrade line and a bar. Down members are not counted in it. A click opens the StartFS window on Overview.
- **Search.** "Search nodes, sites and releases".
- **Node rows** (`NodeRow.qml`). A tile (the desktop glyph for this node, a server for the others; red when down or lost; it pulses while restarting), the host name, tags (THIS NODE, a state other than up, BEHIND, UPGRADE FAILED, OLDER RELEASE), a status line (the release or upgrade step, used of offered, round trip; for a down node, last seen and the problem), and a meter of the share of the offer used (from `stats`). Actions: **Restart now** (accent; only on this node, only when its upgrade waits on its mount; runs `upgrade --force`), details (node window on Status), settings (node window on Settings), and remove (a trash can, only for down or lost members; it asks inline "Remove HOST? Remove / No" and lapses after 4 seconds).
- **Groups.** By site when any member declares one: this node's site first, then by name, no site last. Otherwise one "NODES" list.
- **Footer.** "+ Invite a node..." runs `startfsgui invite`, shows the join command with a **Copy** button and copies it. On the right the notice, or "Esc to close".
- **Keys.** Type to search, Up/Down, Enter for details, Delete to remove (it asks), Ctrl+R look again, Ctrl+S settings. Esc clears the search, then closes.

## Node window

`NodeView.qml`, a `SettingsWindow` like StartAppImage's per-app settings. The title is the host with a glyph; the small caps line is `THIS NODE` or `NODE`, then the release.

| Page | Holds |
|---|---|
| Status | State, upgrade step, why it is unreachable, last seen, stand-in copies, behind, address, member number, site, release and protocol, round trip |
| Storage | Offered, weight, on disk, chunks, compression, share, waiting to be freed. For this node also waiting for replication, cache, scrub, garbage collection, metadata |
| Activity | This node only. `startfs activity`, read every 5 seconds while the page shows: sending and receiving rates, in flight, queue, work loop, memory, CPU, written, read cache, pressures, per-peer traffic |
| Settings | Space offered, weight, site (text boxes). See [Settings](#settings) |
| Maintenance | This node: **Restart on the new release**, the **Activity counters** switch, **Daemon log** (journalctl in a terminal, `startfsgui logs`), **Leave the filesystem** (two clicks). Another node: **Reinstall StartFS** (StartFS's installer over ssh, pinned to the cluster's release, for nodes older than 1.10 or broken; its output shows under the button), **Remove from the filesystem** (two clicks, only when down or lost) |

The footer says "Changes apply instantly" for this node and "Changes apply over ssh" for another.

## Upgrading

Since 1.10.0 `startfs update` upgrades every node from any node, one at a time (all together when the protocol changes). So the manager has no per-node update. The upgrade is on the StartFS window's Upgrade page: what the nodes run and who lags, the newest release with **Check again**, a Release box (empty means the newest) and **Upgrade every node** (two clicks), with the progress as its note. The header's **Upgrade to vX** opens it.

Progress is read from `status --json`: every 2 seconds while the window is open during an upgrade, every 10 seconds when it is closed. While an upgrade restarts this node, the last status is kept instead of "cannot reach". A member that only lags a release, with no upgrade step, is not shown as upgrading: it has the OLDER RELEASE tag and the header offers the upgrade. When this node's upgrade waits on its mount, **Restart now** (or the node's Maintenance page) runs `upgrade --force`. A notification says when an upgrade finishes or stops, and when the data stops being safe while the manager is closed.

## Storage figures

The StartFS window's Storage page shows the size of the files, what is left after deduplication, what is kept across the nodes, the usable space, and this node's disk use with its compression and share. They are left out until there are files and on a daemon that does not report them (`efficiency` of `startfs status --json`). Each node's use of its offer comes from `startfs stats --json`: read when the manager opens, on look again and every 30 seconds while open, never on the status poll, because it asks every member. A member that did not answer says "no answer".

## StartFS window

`SetupView.qml`, opened by the gear. Pages: Overview (data, copies, nodes up, usable, repair, missing copies, re-checking, chunks only on a down node, partial view, warnings, conflict copies, scrub), Storage, Upgrade, Filesystem (name, copies 1 to 5, **Free deleted data now** = `startfs purge`, two clicks; repair wait and sleeping-node cover read-only), then General, Bar and Window. The first-run offer opens it on General.

## Settings

| Page | Setting | Control | Applies with |
|---|---|---|---|
| Node: Settings | Space offered | text, under its label | `set offer [--host H]` (on Enter or when the box loses focus) |
| Node: Settings | Weight | text | `set weight [--host H]` |
| Node: Settings | Site | text | `set site [--host H]` |
| Node: Maintenance | Activity counters (this node) | switch | `set activity` |
| StartFS: Upgrade | Release | text | read by **Upgrade every node**, `upgrade [vX.Y.Z]` |
| StartFS: Filesystem | Copies | choice 1 to 5 | `set copies` |
| StartFS: General | App launcher entry | switch | `setup --launcher` |
| StartFS: General | Command line | switch | `setup --cli` |
| StartFS: Bar | Bar icon | switch | `setup --bar-icon` |
| StartFS: Window | Remember size | switch | `setup --remember-size` |
| StartFS: Window | Remember position | switch | `setup --remember-position` |

Sizes are whole numbers with an optional unit (`500M`, `10G`), with no decimals, as `startfs` reads them. A remote node's settings are disabled when it is not up. The IPC `node HOST` opens a node's window.

## Decision log

| Date | Decision | Why |
|---|---|---|
| 2026-10-20 | A member that only lags a release, with no upgrade step, is tagged OLDER RELEASE and not shown as upgrading. | Nothing is happening to it; the header offers the upgrade. Showing it as in progress made a calm cluster look busy. |
| 2026-10-20 | Down members are not counted in the upgrade progress. | They cannot take a step; counting them made the bar stall for a node nobody was waiting on. |
| 2026-10-20 | `stats` is read when the manager opens, on look again and every 30 seconds while open. A notification says when an upgrade finishes or stops, and when the data stops being safe while the manager is closed. | `stats` asks every member, so not on the 5 second poll. The user is not watching the manager during an upgrade. |
| 2026-10-20 | While an upgrade restarts this node, the last status is kept instead of "cannot reach". Progress is polled every 2 seconds with the window open, 10 closed. | The daemon is down for a moment by design; an error would read as a failure. |
| 2026-10-20 | The per-node "Update" over ssh is gone. The upgrade is the StartFS window's Upgrade page, two clicks. | Since 1.10.0 `startfs update` upgrades every node from any node, one at a time. A per-node button would fight it. |
| 2026-10-20 | Unknown and Upgrading members are drawn neutral; only down, lost and failed are red. Status dots are neutral when healthy; accent is for an upgrade step that is happening and the one action to take. | Red that comes and goes during a normal restart teaches the user to ignore it. |
| 2026-10-20 | The manager is a list of nodes with search, a window per node and a health banner, modelled on StartAppImage. | Each node is like an app. The dashboard could not hold per-node actions, and the family reads alike. |
| 2026-10-20 | `SettingsWindow.qml` is StartDrive's copy plus an `info` field type and a glyph slot sized to the glyph; `Switch.qml` is copied too. | Node and cluster facts are read-only values; icon-font glyphs draw wider than they advance. Both belong upstream. |
| 2026-10-20 | Space offered moved from the StartFS window to each node's Settings page. | The offer is per node, and the node window can set it on another node over ssh. |
| 2026-10-17 | The per-member storage figures are asked for when the window opens, not on the poll. | `startfs stats` queries every member at that moment; every 5 seconds would be a steady load on the whole cluster for a number that changes slowly. |
| 2026-10-17 | Updating a node is two presses, and the installer's output is shown, not hidden behind a spinner. | It restarts a daemon (for this node, the mount under the user's files); a mis-click should not do that, and a failure must be readable where it happened. |
| 2026-10-17 | Node settings live in the settings window, not on the manager. | The shared rules put settings in the settings window; the first slice had them on the manager, which made it look bare and unlike the family. |
| 2026-10-17 | The manager shows warnings, repair, unreplicated chunks, conflicts and unreachable members only when there is something to say. | `startfs status --json` carries them; an empty "all fine" section is noise. |
