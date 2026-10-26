import React from 'react';
import { AbsoluteFill, interpolate, spring, useCurrentFrame, useVideoConfig } from 'remotion';
import { loadFont as loadMono } from '@remotion/google-fonts/JetBrainsMono';
import { loadFont as loadSans } from '@remotion/google-fonts/Inter';
import rec from './recordings.json';

// Everything shown in the terminal comes verbatim from recordings/*.txt,
// recorded on macOS 26.2 with Claude Desktop 3.6556.2. The instance panel on
// the right is an illustration driven by those same output lines.

const { fontFamily: MONO } = loadMono('normal', { weights: ['400', '700'], subsets: ['latin'] });
const { fontFamily: SANS } = loadSans('normal', { weights: ['400', '500', '600', '700', '800'], subsets: ['latin'] });

export const FPS = 30;

const C = {
  bg: '#0a0b0f',
  panel: '#12141b',
  panelEdge: '#232733',
  text: '#d9dde6',
  dim: '#7c8496',
  faint: '#3a404f',
  green: '#4ade80',
  cyan: '#67e8f9',
  yellow: '#fbbf24',
  red: '#f87171',
  coral: '#d97757',
  violet: '#a78bfa',
};

type Rec = { command: string; output: string[] };
const R = rec as Record<string, Rec>;

// ---------------------------------------------------------------------------
// Timeline
// ---------------------------------------------------------------------------

const TITLE = 84;
const CHARS_PER_FRAME = 1.4;
const LINE_FRAMES = 3;
const WAIT_FRAMES = 66; // the sign-in itself, in the browser
const END = 110;

const SCENES: { key: string; caption: string; hold: number }[] = [
  { key: 'add', caption: 'Create a profile', hold: 34 },
  { key: 'login', caption: 'Guided sign-in: the other instances step aside', hold: 46 },
  { key: 'list', caption: 'Every profile, its PID and sign-in state', hold: 40 },
  { key: 'open', caption: 'Bring a running profile to the front, by PID', hold: 44 },
  { key: 'cli', caption: 'Claude Code CLI gets its own sign-in too', hold: 36 },
  { key: 'doctor', caption: 'Check the whole setup', hold: 60 },
];

type Line = { text: string; kind: 'cmd' | 'out'; at: number; typedFrom?: number };
type Step = { key: string; caption: string; start: number; end: number; typeEnd: number; waitAt?: number };

const build = () => {
  const lines: Line[] = [];
  const steps: Step[] = [];
  let t = TITLE;
  for (const s of SCENES) {
    const r = R[s.key];
    const start = t;
    t += 8;
    const typeEnd = t + Math.ceil(r.command.length / CHARS_PER_FRAME);
    lines.push({ text: r.command, kind: 'cmd', at: start, typedFrom: t });
    t = typeEnd + 7;
    let waitAt: number | undefined;
    for (const o of r.output) {
      lines.push({ text: o, kind: 'out', at: t });
      t += LINE_FRAMES;
      if (s.key === 'login' && o.startsWith('Waiting up to')) {
        waitAt = t;
        t += WAIT_FRAMES;
      }
    }
    t += s.hold;
    steps.push({ key: s.key, caption: s.caption, start, end: t, typeEnd, waitAt });
  }
  return { lines, steps, end: t };
};

const TL = build();
export const DURATION = TL.end + END;

// ---------------------------------------------------------------------------
// Instance panel state, derived from output lines that are already visible
// ---------------------------------------------------------------------------

type Inst = { id: string; title: string; sub: string; account: string; running: boolean; signedIn: boolean; front: boolean; cli: boolean; visible: boolean };

const initial = (): Record<string, Inst> => ({
  main: { id: 'main', title: 'Claude', sub: 'main instance', account: 'Account 1', running: true, signedIn: true, front: false, cli: false, visible: true },
  compte2: { id: 'compte2', title: 'compte2', sub: 'another profile', account: 'Account 2', running: true, signedIn: true, front: false, cli: false, visible: true },
  work: { id: 'work', title: 'work', sub: 'twindesk profile', account: 'Account 2', running: false, signedIn: false, front: false, cli: false, visible: false },
});

const EFFECTS: [RegExp, (s: Record<string, Inst>) => void][] = [
  [/profile 'work' created/, (s) => { s.work.visible = true; }],
  [/main instance stopped/, (s) => { s.main.running = false; }],
  [/profile 'compte2' stopped/, (s) => { s.compte2.running = false; }],
  [/profile 'work' is running/, (s) => { s.work.running = true; }],
  [/profile 'work' is signed in/, (s) => { s.work.signedIn = true; }],
  [/main instance running again/, (s) => { s.main.running = true; }],
  [/profile 'compte2' running again/, (s) => { s.compte2.running = true; }],
  [/bringing it to the front/, (s) => { s.work.front = true; }],
  [/\(Claude Code\)/, (s) => { s.work.cli = true; }],
  // `list` shows only 'work': compte2 had been removed by then.
  [/^work\s+running/, (s) => { s.compte2.visible = false; }],
];

const stateAt = (frame: number) => {
  const s = initial();
  const changed: Record<string, number> = {};
  for (const l of TL.lines) {
    if (l.kind !== 'out' || l.at > frame) continue;
    for (const [re, fx] of EFFECTS) {
      if (re.test(l.text)) {
        fx(s);
        const id = Object.keys(s).find((k) => l.text.includes(`'${k}'`) || (k === 'main' && l.text.includes('main instance')));
        if (id) changed[id] = l.at;
        if (re.source.includes('Claude Code')) changed.work = l.at;
      }
    }
  }
  return { s, changed };
};

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

const colorize = (text: string): React.ReactNode => {
  const lead: [RegExp, string][] = [
    [/^ok /, C.green],
    [/^-> /, C.cyan],
    [/^warning: /, C.yellow],
    [/^error: /, C.red],
  ];
  for (const [re, color] of lead) {
    const m = text.match(re);
    if (m) {
      return (
        <>
          <span style={{ color, fontWeight: 700 }}>{m[0].trimEnd()}</span> {text.slice(m[0].length)}
        </>
      );
    }
  }
  if (/^PROFILE\s+STATE/.test(text)) return <span style={{ color: C.dim }}>{text}</span>;
  if (/^ {2}\d\. /.test(text)) return <span style={{ color: C.text }}>{text}</span>;
  return text;
};

const COLS = 92;
const ROWS = 23;
// A command line also carries an 8px gap above it (0.4 of a 20px row).
const rowsOf = (l: Line) => Math.max(1, Math.ceil(l.text.length / COLS)) + (l.kind === 'cmd' ? 0.4 : 0);

const Terminal: React.FC<{ frame: number }> = ({ frame }) => {
  const visible = TL.lines.filter((l) => l.at <= frame);
  // Keep the last ROWS visual rows, like a real terminal scrolling.
  let rows = 0;
  let first = visible.length;
  while (first > 0 && rows + rowsOf(visible[first - 1]) <= ROWS) {
    rows += rowsOf(visible[first - 1]);
    first--;
  }
  const shown = visible.slice(first);
  const last = shown[shown.length - 1];
  const cursorOn = Math.floor(frame / 15) % 2 === 0;
  const step = TL.steps.find((s) => frame >= s.start && frame < s.end);
  const waiting = step?.waitAt !== undefined && frame >= step.waitAt && frame < step.waitAt + WAIT_FRAMES;

  return (
    <div style={{ fontFamily: MONO, fontSize: 13.2, lineHeight: '20px', color: C.text, whiteSpace: 'pre-wrap', overflowWrap: 'break-word', fontVariantLigatures: 'none' }}>
      {shown.map((l, i) => {
        if (l.kind === 'cmd') {
          const n = Math.max(0, Math.min(l.text.length, Math.floor((frame - (l.typedFrom ?? l.at)) * CHARS_PER_FRAME)));
          const typing = l === last && n < l.text.length;
          return (
            <div key={i} style={{ marginTop: i === 0 ? 0 : 8 }}>
              <span style={{ color: C.coral, fontWeight: 700 }}>❯ </span>
              <span style={{ color: '#fff' }}>{l.text.slice(0, n)}</span>
              {(typing || (l === last && cursorOn)) && <span style={{ background: C.text, color: C.bg }}> </span>}
            </div>
          );
        }
        return <div key={i}>{colorize(l.text)}</div>;
      })}
      {last && last.kind === 'out' && !waiting && frame >= last.at + 8 && cursorOn && (
        <div style={{ marginTop: 8 }}>
          <span style={{ color: C.coral, fontWeight: 700 }}>❯ </span>
          <span style={{ background: C.text }}> </span>
        </div>
      )}
      {waiting && (
        <div style={{ color: C.faint, marginTop: 2 }}>
          {'⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'[Math.floor(frame / 3) % 10]}
        </div>
      )}
    </div>
  );
};

const Dot: React.FC<{ color: string; pulse?: boolean; frame: number }> = ({ color, pulse, frame }) => {
  const k = pulse ? 0.5 + 0.5 * Math.sin(frame / 5) : 1;
  return (
    <div style={{ width: 9, height: 9, borderRadius: 9, background: color, boxShadow: `0 0 ${10 * k}px ${color}`, opacity: 0.6 + 0.4 * k }} />
  );
};

const Card: React.FC<{ inst: Inst; frame: number; changedAt?: number; waiting: boolean; index: number }> = ({ inst, frame, changedAt, waiting, index }) => {
  const { fps } = useVideoConfig();
  const flash = changedAt !== undefined ? interpolate(frame - changedAt, [0, 4, 22], [0, 1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' }) : 0;
  const appear = inst.id === 'work' ? spring({ frame: frame - (changedAt ?? 0), fps, config: { damping: 18 } }) : 1;
  const status = !inst.running ? 'closed' : inst.signedIn ? 'signed in' : waiting ? 'signing in…' : 'not signed in';
  const statusColor = !inst.running ? C.dim : inst.signedIn ? C.green : C.yellow;
  const front = inst.front;
  return (
    <div
      style={{
        position: 'relative',
        transform: `translateY(${(1 - appear) * 24}px) scale(${front ? 1.03 : 1})`,
        opacity: inst.visible ? appear * (inst.running ? 1 : 0.5) : 0,
        display: inst.visible || inst.id === 'work' ? 'block' : 'none',
        background: front ? 'linear-gradient(135deg, #1d1712, #151821)' : C.panel,
        border: `1px solid ${front ? C.coral : flash > 0.01 ? '#4b5466' : C.panelEdge}`,
        boxShadow: front ? `0 0 0 1px ${C.coral}55, 0 18px 50px -12px ${C.coral}66` : `0 10px 30px -18px #000`,
        borderRadius: 14,
        padding: '14px 16px',
        marginBottom: 12,
        fontFamily: SANS,
        transition: 'none',
        zIndex: 10 - index,
      }}
    >
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <div
          style={{
            width: 30,
            height: 30,
            borderRadius: 8,
            background: inst.id === 'main' ? C.coral : inst.id === 'work' ? C.violet : '#5b8def',
            display: 'flex',
            alignItems: 'center',
            justifyContent: 'center',
            color: '#0b0b0f',
            fontWeight: 800,
            fontSize: 15,
          }}
        >
          {inst.account.slice(-1)}
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ color: '#fff', fontWeight: 650, fontSize: 15 }}>{inst.title}</div>
          <div style={{ color: C.dim, fontSize: 12 }}>{inst.sub}</div>
        </div>
        {front && <div style={{ fontSize: 11, color: C.coral, fontWeight: 700, letterSpacing: 0.6 }}>FRONT</div>}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginTop: 12, fontSize: 12.5 }}>
        <Dot color={statusColor} pulse={inst.running && !inst.signedIn} frame={frame} />
        <span style={{ color: statusColor, fontWeight: 600 }}>{status}</span>
        <span style={{ color: C.faint }}>·</span>
        <span style={{ color: C.text }}>{inst.signedIn || inst.id !== 'work' ? inst.account : '—'}</span>
        {inst.cli && (
          <span style={{ marginLeft: 'auto', fontFamily: MONO, fontSize: 11, color: C.cyan, border: `1px solid ${C.cyan}55`, borderRadius: 6, padding: '1px 6px' }}>
            + CLI
          </span>
        )}
      </div>
    </div>
  );
};

const Window: React.FC<{ children: React.ReactNode; title: string; style?: React.CSSProperties }> = ({ children, title, style }) => (
  <div
    style={{
      background: 'linear-gradient(180deg, #13161e, #0f1117)',
      border: `1px solid ${C.panelEdge}`,
      borderRadius: 14,
      boxShadow: '0 30px 80px -30px rgba(0,0,0,0.9), inset 0 1px 0 rgba(255,255,255,0.04)',
      overflow: 'hidden',
      ...style,
    }}
  >
    <div style={{ height: 34, display: 'flex', alignItems: 'center', padding: '0 14px', borderBottom: `1px solid ${C.panelEdge}`, gap: 8 }}>
      {['#ff5f57', '#febc2e', '#28c840'].map((c) => (
        <div key={c} style={{ width: 11, height: 11, borderRadius: 11, background: c, opacity: 0.85 }} />
      ))}
      <div style={{ flex: 1, textAlign: 'center', fontFamily: SANS, fontSize: 12, color: C.dim, marginRight: 50 }}>{title}</div>
    </div>
    {children}
  </div>
);

// ---------------------------------------------------------------------------
// Scenes
// ---------------------------------------------------------------------------

const Backdrop: React.FC<{ frame: number }> = ({ frame }) => (
  <AbsoluteFill style={{ background: C.bg }}>
    <AbsoluteFill
      style={{
        background: `radial-gradient(900px 500px at ${20 + Math.sin(frame / 90) * 6}% 0%, ${C.coral}22, transparent 60%), radial-gradient(800px 500px at 100% 100%, ${C.violet}1c, transparent 60%)`,
      }}
    />
    <AbsoluteFill
      style={{
        backgroundImage: `linear-gradient(${C.panelEdge}33 1px, transparent 1px), linear-gradient(90deg, ${C.panelEdge}33 1px, transparent 1px)`,
        backgroundSize: '48px 48px',
        maskImage: 'radial-gradient(ellipse at center, black 30%, transparent 75%)',
        WebkitMaskImage: 'radial-gradient(ellipse at center, black 30%, transparent 75%)',
      }}
    />
  </AbsoluteFill>
);

const Title: React.FC<{ frame: number }> = ({ frame }) => {
  const { fps } = useVideoConfig();
  const a = spring({ frame, fps, config: { damping: 16 } });
  const split = spring({ frame: frame - 18, fps, config: { damping: 14, mass: 0.8 } });
  const out = interpolate(frame, [TITLE - 14, TITLE], [1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  const mini = (color: string, label: string, dx: number, rot: number) => (
    <div
      style={{
        position: 'absolute',
        width: 150,
        height: 100,
        left: '50%',
        top: 0,
        marginLeft: -75,
        transform: `translateX(${dx * split}px) rotate(${rot * split}deg)`,
        background: C.panel,
        border: `1px solid ${C.panelEdge}`,
        borderRadius: 12,
        boxShadow: `0 20px 50px -20px ${color}aa`,
        overflow: 'hidden',
      }}
    >
      <div style={{ height: 20, borderBottom: `1px solid ${C.panelEdge}`, display: 'flex', alignItems: 'center', gap: 5, padding: '0 8px' }}>
        {['#ff5f57', '#febc2e', '#28c840'].map((c) => (
          <div key={c} style={{ width: 6, height: 6, borderRadius: 6, background: c }} />
        ))}
      </div>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: 80 }}>
        <div style={{ width: 38, height: 38, borderRadius: 10, background: color, color: '#0b0b0f', fontFamily: SANS, fontWeight: 800, fontSize: 20, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{label}</div>
      </div>
    </div>
  );
  return (
    <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center', opacity: out }}>
      <div style={{ position: 'relative', width: 400, height: 110, marginBottom: 34, opacity: a }}>
        {mini(C.violet, '2', 90, 4)}
        {mini(C.coral, '1', -90, -4)}
      </div>
      <div style={{ fontFamily: SANS, fontWeight: 800, fontSize: 78, letterSpacing: -2.5, color: '#fff', transform: `translateY(${(1 - a) * 20}px)`, opacity: a }}>
        twindesk
      </div>
      <div style={{ fontFamily: SANS, fontSize: 24, color: C.dim, marginTop: 8, opacity: interpolate(frame, [14, 30], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' }) }}>
        Several Claude Desktop accounts, side by side.
      </div>
    </AbsoluteFill>
  );
};

const Main: React.FC<{ frame: number }> = ({ frame }) => {
  const { fps } = useVideoConfig();
  const enter = spring({ frame: frame - TITLE + 6, fps, config: { damping: 20 } });
  const leave = interpolate(frame, [TL.end, TL.end + 14], [1, 0], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  const step = TL.steps.find((s) => frame >= s.start && frame < s.end) ?? TL.steps[TL.steps.length - 1];
  const { s, changed } = stateAt(frame);
  const waiting = step.waitAt !== undefined && frame >= step.waitAt && frame < step.waitAt + WAIT_FRAMES;
  const capIn = interpolate(frame - step.start, [0, 10], [0, 1], { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' });
  const idx = TL.steps.indexOf(step);
  return (
    <AbsoluteFill style={{ padding: '38px 44px', opacity: enter * leave, transform: `translateY(${(1 - enter) * 30}px)` }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14, height: 40, marginBottom: 18 }}>
        <div style={{ fontFamily: SANS, fontWeight: 800, fontSize: 22, color: '#fff', letterSpacing: -0.6 }}>twindesk</div>
        <div style={{ width: 1, height: 22, background: C.panelEdge }} />
        <div style={{ fontFamily: SANS, fontSize: 18, color: C.text, opacity: capIn, transform: `translateX(${(1 - capIn) * 10}px)` }}>{step.caption}</div>
        <div style={{ marginLeft: 'auto', display: 'flex', gap: 6 }}>
          {TL.steps.map((_, i) => (
            <div key={i} style={{ width: i === idx ? 22 : 7, height: 7, borderRadius: 7, background: i <= idx ? C.coral : C.faint }} />
          ))}
        </div>
      </div>
      <div style={{ display: 'flex', gap: 22, flex: 1 }}>
        <Window title="zsh — twindesk" style={{ flex: 1 }}>
          <div style={{ padding: '16px 18px', height: 520, overflow: 'hidden' }}>
            <Terminal frame={frame} />
          </div>
        </Window>
        <div style={{ width: 300 }}>
          <div style={{ fontFamily: SANS, fontSize: 11, letterSpacing: 1.4, color: C.dim, fontWeight: 600, margin: '8px 4px 12px' }}>
            CLAUDE INSTANCES <span style={{ color: C.faint, letterSpacing: 0.4, fontWeight: 400 }}>· illustration</span>
          </div>
          {(['main', 'compte2', 'work'] as const).map((k, i) => (
            <Card key={k} inst={s[k]} frame={frame} changedAt={changed[k]} waiting={waiting && k === 'work'} index={i} />
          ))}
          <div style={{ opacity: waiting ? 1 : 0, marginTop: 6, fontFamily: SANS, fontSize: 12.5, color: C.yellow, display: 'flex', gap: 8, alignItems: 'center' }}>
            <Dot color={C.yellow} pulse frame={frame} /> signing in to account 2 in the browser…
          </div>
        </div>
      </div>
    </AbsoluteFill>
  );
};

const End: React.FC<{ frame: number }> = ({ frame }) => {
  const { fps } = useVideoConfig();
  const a = spring({ frame: frame - TL.end - 8, fps, config: { damping: 18 } });
  const lines = [
    'git clone … && ./install.sh',
    'twindesk add work && twindesk login work',
  ];
  return (
    <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center', opacity: a }}>
      <div style={{ fontFamily: SANS, fontWeight: 800, fontSize: 60, letterSpacing: -2, color: '#fff' }}>twindesk</div>
      <div style={{ fontFamily: SANS, fontSize: 21, color: C.dim, marginTop: 6 }}>Open source · MIT · No sudo · No telemetry</div>
      <div style={{ marginTop: 30, background: C.panel, border: `1px solid ${C.panelEdge}`, borderRadius: 12, padding: '16px 22px', fontFamily: MONO, fontSize: 15, color: C.text }}>
        {lines.map((l) => (
          <div key={l}>
            <span style={{ color: C.coral, fontWeight: 700 }}>❯ </span>
            {l}
          </div>
        ))}
      </div>
      <div style={{ marginTop: 34, fontFamily: SANS, fontSize: 13.5, color: C.dim, textAlign: 'center', lineHeight: 1.6 }}>
        Terminal output recorded on macOS 26.2 with Claude Desktop 3.6556.2 (paths anonymized).
        <br />
        Not affiliated with Anthropic. Claude is a trademark of Anthropic, PBC.
      </div>
    </AbsoluteFill>
  );
};

export const Demo: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: C.bg }}>
      <Backdrop frame={frame} />
      {frame < TITLE && <Title frame={frame} />}
      {frame >= TITLE - 8 && frame < TL.end + 16 && <Main frame={frame} />}
      {frame >= TL.end && <End frame={frame} />}
    </AbsoluteFill>
  );
};

