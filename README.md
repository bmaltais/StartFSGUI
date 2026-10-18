# StartFSGUI

An [Omarchy](https://omarchy.org) shell plugin for [StartFS](https://github.com/bmaltais/StartFS): see whether your data is safe, who is in the filesystem, and change this node's space offered and the number of copies.

Built like the other Start apps (StartDrive, StartAppImage): a Quickshell plugin, a `bin/startfsgui` command that does the work, and the shared [omarchy-plugin-devkit](https://github.com/bmaltais/omarchy-plugin-devkit) in `scripts/devkit`.

## Status

0.2.0: a dashboard (is the data safe, copies, usable space, members, repair, warnings and conflicts), a settings window in the Start family's look (this node's space offered and copies, launcher entry, command line, bar icon, remembered window), a movable and resizable manager, and an optional bar icon that turns red when the data is not safe. Not yet: create/join/leave/remove/revoke, `config.toml` keys.

It reads `startfs status --json` when your `startfs` has it (added after 1.0.6) and the plain text of older builds otherwise.

## Develop

```sh
git submodule update --init scripts/devkit
DEV_WATCH=0 scripts/dev up      # a nested session, running on a fixture (STARTFSGUI_DEMO=1); `startfs` is never run
scripts/dev open && scripts/dev shot FILE
scripts/dev down
scripts/check.sh                # shellcheck, qmllint, manifest, CLI tests, parser tests
```

`bin/startfsgui` is the only thing that runs `startfs`. In demo mode it shadows `startfs` with a fixture, so a click in the test session cannot touch your real cluster.
