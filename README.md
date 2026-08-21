# OpenLogi Flatpak

An unofficial Flatpak package for [OpenLogi](https://github.com/AprilNEA/OpenLogi),
built from upstream release tarballs and published as a signed OSTree repository.

**Packaging only. The source is unmodified.** Application bugs belong
[upstream](https://github.com/AprilNEA/OpenLogi/issues); packaging bugs belong here.

## Why this exists

OpenLogi publishes `.deb`, `.rpm` and `.pkg.tar.zst` packages, but no repository
to serve them from, and its in-app updater ships no Linux artifact at all
(`xtask release latest-json` classifies only `.dmg`, `.msi` and `.zip`, while the
updater asks for `tar.gz` on Linux). So every Linux upgrade is a manual download
of a newer package.

A Flatpak remote closes that: install once, and `flatpak update` (or GNOME
Software and KDE Discover in the background) keeps it current.

## Install

```sh
flatpak remote-add --if-not-exists --user openlogi \
  https://aalmansadath.github.io/openlogi-flatpak/openlogi.flatpakrepo
flatpak install --user openlogi org.openlogi.OpenLogi
```

## One-time host setup

A Flatpak cannot write to `/etc`, so OpenLogi's udev rules have to be installed
on the host. **Until you do this, no devices are detected at all.** The sandbox
is allowed to reach `/dev/hidraw*`, `/dev/uinput` and `/dev/input/event*`, but
the kernel still refuses your user access to them.

The rules ship inside the application, so there is nothing to download:

```sh
flatpak run --command=cat org.openlogi.OpenLogi \
  /app/share/openlogi/udev/70-openlogi.rules \
  | sudo tee /etc/udev/rules.d/70-openlogi.rules

echo uinput | sudo tee /etc/modules-load.d/openlogi.conf
sudo modprobe uinput

sudo udevadm control --reload-rules
sudo udevadm trigger
```

Then quit OpenLogi completely and start it again:

```sh
flatpak kill org.openlogi.OpenLogi
```

### Why each part is there

- **The rules** grant your active-seat user access to Logitech `hidraw` nodes,
  to `/dev/uinput`, and to the `/dev/input/event*` node of any Logitech mouse.
  Keyboards are deliberately excluded, so a Logitech keyboard's keystrokes never
  become readable session-wide.
- **The `uinput` lines** matter on a machine that has never loaded that module.
  The rule's `static_node=uinput` creates the device node, but its `uaccess` tag
  only grants an ACL in response to a device event, and with no module loaded
  there is no device in sysfs for `udevadm trigger` to act on, so the node stays
  `root:root 0600`. Opening it would autoload the module, except opening is what
  the missing permission forbids. `modules-load.d` makes the load survive a
  reboot; `modprobe` applies it now.
- **The restart** is needed because closing the window is not enough. OpenLogi's
  agent is a separate, always-on process that outlives the GUI, and it installs
  its input hook once at startup, so a permission granted while it is running
  never reaches it. Device enumeration recovers on its own within seconds, which
  makes this easy to miss: everything looks repaired except button remapping.

If a Bluetooth device is still not detected, toggle it off and on. `udevadm
trigger` applies rules to new device nodes but will not always re-tag one that
was already attached.

### Conflicts with other Logitech tools

Solaar and logiops both talk to the same devices. `solaar-udev` in particular
grants `hidraw` and `uinput` but nothing under `/dev/input`, which leaves
OpenLogi able to read battery and set DPI while button remapping silently does
not work. Stop them before diagnosing anything:

```sh
sudo systemctl stop logid
```

## What is packaged here, and why

Nothing patches the source. Only the build environment lives in this repository,
because that is genuinely packaging's problem:

- **rustup instead of the SDK's Rust extension.** The workspace sets
  `rust-version` to whatever stable is current, while
  `org.freedesktop.Sdk.Extension.rust-stable` trails it by weeks: 1.97.1 when
  the workspace asked for 1.98, which cargo refuses outright. rustup installs
  what `rust-toolchain.toml` names, so builds track the project rather than the
  SDK's release cadence.
- **`llvm20`**, because `openlogi-camera` pulls `v4l2-sys-mit`, whose build
  script runs bindgen and dlopens libclang. The base SDK ships none.
- **A `.desktop` file and AppStream metadata.** Upstream's `.desktop` is written
  for a system install, and upstream ships no AppStream metadata.
- **Icons rescaled to 512px and below.** `flatpak build-export` rejects the
  1024×1024 source outright.

## Building locally

```sh
flatpak-builder --user --install --force-clean build org.openlogi.OpenLogi.yml
```

The manifest pins a release tarball and its SHA-256, so it builds standalone. CI
rewrites both for whichever release it is publishing.

## Publishing

`.github/workflows/publish.yml` builds x86_64 and aarch64, merges them into one
OSTree repository, signs it, and deploys to GitHub Pages. It runs on a daily
schedule (upstream releases are not events this repository can observe) and
exits early when the latest release is already published. A manual dispatch can
build any tag.

Publishing requires a `FLATPAK_GPG_PRIVATE_KEY` secret. Without it the build
still runs and uploads artifacts, and the publish job is skipped: a fork is inert
rather than failing.

Signing covers both the summary **and** the individual commits. Clients verify
the commit they pull, so a summary-only signature fails every install with
`GPG verification enabled, but no signatures found`.

## Not on Flathub

This builds with network access so cargo can resolve crates.io and the
workspace's git dependencies. Flathub requires vendored, offline builds. That is
achievable (`cargo vendor` covers all 985 crates and all 8 git sources) with
one wrinkle: `gpui-component`'s `themes/` directory sits at its repository root
rather than inside the crate, so vendoring never captures it and the build script
cannot find it. A Flathub manifest would supply it as a separate pinned source.

## Licence

The packaging in this repository is MIT. OpenLogi itself is dual-licensed
MIT/Apache-2.0; its `design/` brand assets are proprietary and are redistributed
here only as the application icon.
