// Prepares the render: turns the real recordings in recordings/*.txt into
// src/recordings.json (so the video shows the recorded output verbatim), and
// copies the Claude Desktop icon from the local app into public/claude.png.
// The icon is Anthropic's; it is read at render time and not committed.
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { execFileSync } from 'node:child_process';

const names = ['add', 'login', 'list', 'open', 'cli', 'doctor'];
const out = {};
for (const n of names) {
  const lines = readFileSync(new URL(`./recordings/${n}.txt`, import.meta.url), 'utf8').replace(/\n$/, '').split('\n');
  out[n] = { command: lines[0].replace(/^\$ /, ''), output: lines.slice(1) };
}
writeFileSync(new URL('./src/recordings.json', import.meta.url), JSON.stringify(out, null, 2) + '\n');
console.log(`wrote src/recordings.json (${names.length} recordings)`);

const icns = process.env.CLAUDE_ICNS ?? '/Applications/Claude.app/Contents/Resources/electron.icns';
if (!existsSync(icns)) {
  console.error(`Claude icon not found at ${icns}: install Claude Desktop or set CLAUDE_ICNS`);
  process.exit(1);
}
mkdirSync(new URL('./public', import.meta.url), { recursive: true });
execFileSync('sips', ['-s', 'format', 'png', icns, '--out', new URL('./public/claude.png', import.meta.url).pathname, '-Z', '512'], { stdio: 'ignore' });
console.log('wrote public/claude.png from the local Claude.app');
