# StartFSGUI

An [Omarchy](https://omarchy.org) shell plugin for [StartFS](https://github.com/bmaltais/StartFS): see whether your data is safe, look at every node of the filesystem, upgrade the cluster, and change what each node offers.

The manager is a list of nodes, laid out like StartAppImage's list of apps: a health banner, a search box, one row per node and an "Invite a node..." line. A node opens its own window (status, storage, activity, settings, maintenance). The gear opens the StartFS window (overview, storage, upgrade, filesystem, and the plugin's own settings).

Built like the other Start apps (StartDrive, StartAppImage): a Quickshell plugin, a `bin/startfsgui` command that does the work, and the shared [omarchy-plugin-devkit](https://github.com/bmaltais/omarchy-plugin-devkit) in `scripts/devkit`.

## Status

0.5.0: follows StartFS 1.10. A node list with a health banner, search and a window per node; the cluster upgrade from the StartFS window (`startfs update` upgrades every node from any node); space offered, weight and site per node; copies, "Free deleted data now" and the daemon's activity; invite a node; remove a member that is gone. 0.4.0: storage figures. 0.2.0: dashboard, settings window, movable manager, optional bar icon that turns red when the data is not safe. Not yet: create/join, `config.toml` keys.

It needs StartFS 1.10 or later for the upgrade and the node details (stats, activity, site, weight). An older daemon still shows the basic status: `startfs status --json` (added after 1.0.6), or the plain text of older builds.

## Commands

`bin/startfsgui` does everything the windows do; every command prints JSON.

```
status | stats | activity            read the cluster, its storage figures, this node's traffic
latest [--refresh]                   the newest stable release (asked of GitHub at most every 6 hours)
logs | version --host H              the daemon's log in a terminal; the release a node runs
set offer|weight|site|copies|activity VALUE [--host H]
upgrade [vX.Y.Z] | upgrade --force   upgrade every node; restart this node now
remove N | leave | purge             drop a lost member; leave; free deleted data
invite [--copy]                      a join command for a new node
install --host H [--self] [--version vX.Y.Z]   StartFS's installer (`update` is a hidden alias)
integration | setup | window | ui    this plugin: what is on, switches, window places, show or hide
```

Sizes are whole numbers with an optional unit (`500M`, `10G`, `2T`), as `startfs` reads them. Run `startfsgui --help` for the options. The shell's IPC takes `open`, `toggle`, `close`, `refresh`, `setup`, `state` and `node HOST`.

## Develop

```sh
git submodule update --init scripts/devkit
DEV_WATCH=0 scripts/dev up      # a nested session, running on a fixture (STARTFSGUI_DEMO=1); `startfs` is never run
scripts/dev open && scripts/dev shot FILE
scripts/dev down
scripts/check.sh                # shellcheck, qmllint, manifest, CLI tests, parser tests
```

`bin/startfsgui` is the only thing that runs `startfs`. In demo mode it shadows `startfs` with a fixture, so a click in the test session cannot touch your real cluster. The fixture is seven nodes in StartFS 1.10.2's JSON shape (sites home and cloud, vps2 down, mini1 one release behind) with a simulated rolling upgrade; this node waits on its mount until `upgrade --force`. `touch ~/.config/startfsgui/demo/healthy` makes the cluster healthy; `rm -rf ~/.config/startfsgui/demo` resets it.
