# Demo video

`docs/demo.gif` and `docs/demo.mp4` are rendered with [Remotion](https://www.remotion.dev) from this folder.

- The terminal shows the output in `recordings/` verbatim. It was recorded on macOS 26.2 with Claude Desktop 3.6556.2 during the real tests of twindesk 0.1.0; the home folder is anonymized to `/Users/you`.
- The "Claude instances" panel is an illustration. Its state changes only when an output line says so (for example `ok main instance stopped`).

To render again (needs Node 18+ and ffmpeg):

```sh
npm ci
npm run render
```
