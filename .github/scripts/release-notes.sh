#!/usr/bin/env bash
# Print the GitHub release notes for one upstream version, to stdout.
#
# Kept out of the workflow so the notes are editable without touching CI, and
# so a release reads the same however it was made. A backfill workflow shared
# this for the versions published before releases existed; it has been removed
# now that the backlog is filled, but the split is worth keeping.
#
#   release-notes.sh VERSION BASE_URL [EXTRA_NOTE]
#
# VERSION is the upstream tag, `v0.7.10`. BASE_URL is the public base of the
# published repository, no trailing slash. EXTRA_NOTE is an optional line
# appended to the intro.
set -euo pipefail

version="${1:?usage: release-notes.sh VERSION BASE_URL [EXTRA_NOTE]}"
base="${2:?usage: release-notes.sh VERSION BASE_URL [EXTRA_NOTE]}"
extra="${3-}"
base="${base%/}"

: "${FLATPAK_ID:?FLATPAK_ID must be set}"
: "${UPSTREAM:?UPSTREAM must be set}"
: "${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set}"

cat <<EOF
OpenLogi **${version}**, built unmodified from the upstream release tarball.
See [upstream's release notes](https://github.com/${UPSTREAM}/releases/tag/${version})
for what changed in the application itself.
${extra:+
${extra}
}
## Install

The repository is the better route: it updates itself, and the bundles below do
not.

\`\`\`sh
flatpak remote-add --if-not-exists --user openlogi \\
  ${base}/openlogi.flatpakrepo
flatpak install --user openlogi ${FLATPAK_ID}
\`\`\`

For a single file, download the bundle for your architecture and:

\`\`\`sh
flatpak install --user ./OpenLogi-${version}-x86_64.flatpak
\`\`\`

The bundles carry the repository as their origin, so an app installed from one
still picks up later releases through \`flatpak update\`.

**After installing, run the [one-time host setup](https://github.com/${GITHUB_REPOSITORY}#one-time-host-setup).**
Without the udev rules on the host, no devices are detected at all.

## Verify

\`\`\`sh
sha256sum -c SHA256SUMS
\`\`\`
EOF
