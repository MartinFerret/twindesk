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

1. Compute the checksum of the release archive:

   ```sh
   curl -fsSL https://github.com/MartinFerret/twindesk/archive/refs/tags/vX.Y.Z.tar.gz | shasum -a 256
   ```

2. In `Formula/twindesk.rb`, update `url` and `sha256`.
3. Check the formula, then install it from the tap and run its test:

   ```sh
   brew audit --strict --online MartinFerret/twindesk/twindesk
   brew upgrade MartinFerret/twindesk/twindesk || brew install MartinFerret/twindesk/twindesk
   brew test MartinFerret/twindesk/twindesk
   ```

4. Commit and push the tap.
