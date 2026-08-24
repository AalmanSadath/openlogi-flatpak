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
  https://openlogi.aalman.dev/openlogi.flatpakrepo
flatpak install --user openlogi org.openlogi.OpenLogi
```

### Or a single file

Every release here also carries a `.flatpak` bundle per architecture, so one
download installs without adding a remote first:

```sh
flatpak install --user ./OpenLogi-v0.7.10-x86_64.flatpak
```

The bundles carry the repository above as their origin, so an app installed from
one still updates through `flatpak update`. Use the remote if you have the
choice; the bundle exists for air-gapped machines and for anyone who wants to
check the thing before trusting a repository with it.

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

`.github/workflows/build.yml` builds x86_64 and aarch64 and is the only place
the build is defined. `.github/workflows/publish.yml` calls it, merges the two
into one OSTree repository, signs it, uploads it to a Cloudflare R2 bucket, and
attaches the bundles to a GitHub release. It runs on a daily schedule (upstream
releases are not events this repository can observe) and exits early when the
latest release is already published. A manual dispatch can build any tag.

`build.yml` is dispatchable on its own, which gives the two `.flatpak` bundles
as workflow artifacts and touches nothing else. It needs no secrets, so a fork
can run it.

Releases are tagged with the upstream version verbatim, `v0.7.10` and so on.
This repository has no version of its own to number: a release here is one
upstream release, packaged. Its bundles come out of the merged and signed store
rather than a second build, so the file on the release page is the same commit
the repository serves.

### Why R2 rather than GitHub Pages

Upstream releases roughly seventeen times a month. Once Flatpak is the
recommended Linux install, an update audience in the low thousands puts several
hundred GB a month through the remote, against a 100 GB Pages allowance that
Pages' own terms do not intend to cover for file distribution. R2 charges nothing
for egress, which also removes the reason to keep the retained history shallow:
the publish job re-downloads the store it is extending on every run.

R2 bills Class B operations rather than bytes, which is the number worth checking
before trusting the above. A full pull of this store is 49 objects, because
OpenLogi installs four binaries and a handful of icons rather than the thousands
of files a typical desktop app carries. At the traffic modelled here that is
about 3.4M operations a month against a 10M free tier -- and that is the worst
case, every update a full pull with no delta applied. Storage at depth 8 is
around 0.6 GB of a 10 GB tier. Egress, the thing that ended the Pages
arrangement, is 1.87 TB and free.

So the Cloudflare custom domain in front of the bucket is not a cost measure. It
is there for the rate limit: the `r2.dev` development URL is throttled and
Cloudflare says plainly not to use it in production. This repo publishes to
`openlogi.aalman.dev`.

### Configuration

Publishing needs all of the following. Any one missing and the publish job skips
itself, so a fork stays inert rather than red.

| Kind | Name | Value |
|---|---|---|
| Secret | `FLATPAK_GPG_PRIVATE_KEY` | ASCII-armoured private key used to sign commits and summary |
| Secret | `R2_ACCOUNT_ID` | Cloudflare account ID, used to build the S3 endpoint |
| Secret | `R2_ACCESS_KEY_ID` | R2 API token, Object Read & Write, scoped to this bucket |
| Secret | `R2_SECRET_ACCESS_KEY` | the token's secret |
| Variable | `R2_BUCKET` | bucket name |
| Variable | `R2_PUBLIC_BASE` | public base URL, no trailing slash, e.g. `https://openlogi.aalman.dev` |

Two more are optional, and only affect the cache purge:

| Kind | Name | Value |
|---|---|---|
| Secret | `CLOUDFLARE_API_TOKEN` | token with Zone / Cache Purge / Purge, scoped to this zone |
| Secret | `CLOUDFLARE_ZONE_ID` | the zone the custom domain lives in |

Without them the publish still succeeds and the purge step says so and exits.

The upload runs in three phases, and the order is load-bearing: content first,
then the `summary` and `refs` that make it reachable, and only then the deletion
of what pruning removed. A single `sync` could publish a summary naming objects
that had not been uploaded yet, which every client in the middle of an update
would see as a broken repository.

Afterwards the mutable paths are purged from Cloudflare's edge by URL: the two
forms of the landing page, the descriptors, `config`, every `summary*` and every
ref file. Never "purge everything" -- that would drop the immutable objects and
deltas too, and every client mid-update would refetch them from R2 as billed
reads, which is the exact cost the year-long cache on them exists to avoid.

The purge is what makes caching those paths safe at all. Two cache rules sit in
front of the bucket: content addressed paths (`objects`, `deltas`,
`delta-indexes`) for a year, and everything mutable for a day. A day rather than
a year because the purge is what normally clears them, and the TTL is only the
ceiling on how wrong the edge can be if a purge ever fails.

`published-version` is deliberately outside both rules. It is read by the
`resolve` job to decide whether upstream is already published, so it is the one
file whose reader is this workflow rather than a user. Caching it saves one read
a day and risks a scheduled run rebuilding a release that is already out, which
costs a full build and a commit on every ref.

A stale pointer is not a broken repository, incidentally: clients keep seeing the
previous release, whose objects are still retained by `--prune-depth`. The
dangerous case is the reverse, a summary naming objects that are not uploaded
yet, and that is what the three phase order above prevents.

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
