# Demo video

`docs/demo.gif` and `docs/demo.mp4` are rendered with [Remotion](https://www.remotion.dev) from this folder.

- Every terminal line comes verbatim from `recordings/`, recorded on macOS 26.2 with Claude Desktop 3.6556.2 during the real tests of twindesk 0.1.0 (home folder anonymized to `/Users/you`). A `…` line marks output lines that were skipped for brevity.
- The two windows are an illustration. Their state changes only when one of those output lines says so (for example `ok main instance stopped`).
- The Claude icon is Anthropic's trademark. It is not committed here: `make-data.mjs` copies it from your local `/Applications/Claude.app` at render time (or from the `.icns` file in `CLAUDE_ICNS`). twindesk is not affiliated with Anthropic.

To render again (macOS with Claude Desktop installed, Node 18+ and ffmpeg):

```sh
npm ci
npm run render
```

`docs/social-preview.png` (the GitHub social preview, 1280x640) comes from the `Social` still: `npm run social`. Its terminal lines are also taken from `recordings/login.txt`.
