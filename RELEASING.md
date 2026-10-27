# Releasing

Maintainer checklist for a new version `X.Y.Z`.

## In this repository

1. Update the version in both scripts: `TWINDESK_VERSION` in `twindesk` and `$script:Version` in `twindesk.ps1`.
2. If a new Claude Desktop version was tested for real, update `TESTED_VERSIONS` / `$script:TestedVersions`, the support table in `README.md` and `TESTED.md` (with the evidence).
3. Add a section to `CHANGELOG.md`.
4. Commit, push, and wait for CI to be green on macOS, Ubuntu and Windows.
5. Tag and release:

   ```sh
   git tag -a vX.Y.Z -m "twindesk X.Y.Z"
   git push origin vX.Y.Z
   gh release create vX.Y.Z --title "twindesk X.Y.Z" --notes-file <notes from CHANGELOG.md> --verify-tag
   ```

## In the Homebrew tap (MartinFerret/homebrew-twindesk)

1. From this repository, with the tap cloned at `~/homebrew-twindesk` (or pass `--tap <path>`):

   ```sh
   scripts/bump-formula.sh X.Y.Z --dry-run   # shows the checksum and the diff
   scripts/bump-formula.sh X.Y.Z             # writes url and sha256 into Formula/twindesk.rb
   ```

   It downloads the release archive, checks that it contains `twindesk` at version X.Y.Z, and computes the checksum (`curl -fsSL <archive> | shasum -a 256`). It never commits or pushes.

2. Check the formula, then install it from the tap and run its test (Homebrew only installs formulae from a tap, not from a file path):

   ```sh
   brew audit --strict --online MartinFerret/twindesk/twindesk
   brew upgrade MartinFerret/twindesk/twindesk || brew install MartinFerret/twindesk/twindesk
   brew test MartinFerret/twindesk/twindesk
   ```

3. Commit and push the tap.
