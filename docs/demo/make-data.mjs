// Turns the real recordings in recordings/*.txt into src/recordings.json,
// so the video shows the recorded output verbatim.
import { readFileSync, writeFileSync } from 'node:fs';

const names = ['add', 'login', 'list', 'open', 'cli', 'doctor'];
const out = {};
for (const n of names) {
  const lines = readFileSync(new URL(`./recordings/${n}.txt`, import.meta.url), 'utf8').replace(/\n$/, '').split('\n');
  out[n] = { command: lines[0].replace(/^\$ /, ''), output: lines.slice(1) };
}
writeFileSync(new URL('./src/recordings.json', import.meta.url), JSON.stringify(out, null, 2) + '\n');
console.log(`wrote src/recordings.json (${names.length} recordings)`);
