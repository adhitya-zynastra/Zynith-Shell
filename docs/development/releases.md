# Releases

Zynith has not made a release yet. This page sets out how releases will be made, and what an ISO must pass before it
is published.

## Versions

- `VERSION` at the top of the repository holds the version being developed (`0.1.0`). The RPMs, the ISO's file name
  and volume label, and `zynith-ui version` take it from there.
- Packages built between releases carry their source in the release field: `0.<date>git<commit>`.
- Before 1.0, a minor version (0.2, 0.3 …) may change configuration in ways that need a migration. Each such change
  is noted in the changelog under its version.

## Making a release

1. Update `CHANGELOG.md`: move *Unreleased* under the new version and date.
2. Commit, then tag the commit: `git tag -a v0.1.0 -m "Zynith 0.1.0"`.
3. Build from the tag. Both builds use `git archive` of the tag, never the working tree:

   ```sh
   iso/build-iso.sh --rev v0.1.0
   ```

4. Validate the ISO against the checklist below and record the results in the release notes.
5. Push the tag and create the GitHub Release by hand. Attach the ISO, its `.sha256`, `manifest.txt` and
   `build-info.txt`. Never commit an ISO or an RPM to the repository.

No workflow creates releases automatically.

## ISO release checklist

An ISO is published as a release only when every item has passed on that exact file (the same SHA-256):

| | Check | How |
|---|---|---|
| 1 | The build is from a tag, with no local changes | `build-info.txt` names the tag's commit and does not say `modified`/`dirty` |
| 2 | The checksum file matches | `sha256sum -c zynith-*.iso.sha256` |
| 3 | The image contains nothing personal | the hygiene check on the source; `manifest.txt` reviewed; no home directories, keys or tokens in the image |
| 4 | It boots in UEFI mode and reaches the Zynith live session | `iso/test-vm.sh live` (OVMF) |
| 5 | It boots in BIOS mode | `iso/test-vm.sh live --bios` |
| 6 | The Zynith UI and the native shell run in the live session; Settings opens | in the VM: `zynith-ui status`, `zynith-ui native status` |
| 7 | The installer starts, and changes no disk until confirmed | `iso/test-vm.sh install`: Anaconda shows the target disk and asks before writing |
| 8 | The installed system boots, with SELinux enforcing and the firewall on | `getenforce`, `firewall-cmd --state` |
| 9 | The first login on the installed system starts Zynith with the default configuration | `zynith-firstrun --list` prints nothing after the first login |
| 10 | Networking, audio and the lock screen work in the VM | NetworkManager connected; PipeWire running; lock and unlock |

Items 4–10 are tested in a virtual machine. Tests on real hardware are recorded separately, by machine, in the
release notes. A release says plainly which machines it has and has not been tested on.

A build that fails any item can still be shared for testing as a **pre-release**, clearly labelled, with the failing
items listed. It is not offered as an installable release.
