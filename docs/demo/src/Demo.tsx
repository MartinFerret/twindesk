import React from 'react';
import { AbsoluteFill, Img, interpolate, spring, staticFile, useCurrentFrame, useVideoConfig } from 'remotion';
import { loadFont as loadMono } from '@remotion/google-fonts/JetBrainsMono';
import { loadFont as loadSans } from '@remotion/google-fonts/Inter';
import rec from './recordings.json';

// Light, simple demo. Every terminal line is taken verbatim from
// recordings/*.txt (recorded on macOS 26.2, Claude Desktop 3.6556.2); "…"
// marks skipped lines. The two windows are an illustration whose state only
// changes when one of those lines says so. The Claude icon is read from the
// local Claude.app at render time (see make-data.mjs) and is not committed.

const { fontFamily: MONO } = loadMono('normal', { weights: ['400', '600'], subsets: ['latin'] });
const { fontFamily: SANS } = loadSans('normal', { weights: ['400', '500', '600', '700', '800'], subsets: ['latin'] });

export const FPS = 30;

const C = {
  bg: '#f5f3ee',
  ink: '#1f1e1d',
  mute: '#6f6b64',
  faint: '#a9a49b',
  line: '#e5e1d8',
  card: '#ffffff',
  coral: '#d97757',
  green: '#2f8a4c',
  amber: '#b7791f',
  blue: '#3b5bdb',
};

type Rec = { command: string; output: string[] };
const R = rec as Record<string, Rec>;
const real = (key: string, re: RegExp) => {
  const l = R[key].output.find((o) => re.test(o));
  if (!l) throw new Error(`no line matching ${re} in recordings/${key}.txt`);
  return l;
};

// ---------------------------------------------------------------------------
// Script
// ---------------------------------------------------------------------------

type Out = { text: string; effect?: string };
type Step = { n: number; title: string; key: string; lines: Out[]; start: number; len: number };

const INTRO = 78;
const STEP_DEFS: Omit<Step, 'start'>[] = [
  { n: 1, title: 'Create a profile', key: 'add', len: 120, lines: [{ text: real('add', /^ok profile 'work' created/), effect: 'work-created' }] },
  {
    n: 2,
    title: 'Sign in to your second account, once',
    key: 'login',
    len: 230,
    lines: [
      { text: real('login', /^ok main instance stopped/), effect: 'main-closed' },
      { text: '…' },
      { text: real('login', /^ok profile 'work' is signed in/), effect: 'work-signed-in' },
      { text: real('login', /^ok main instance running again/), effect: 'main-back' },
    ],
  },
  { n: 3, title: 'Use both, side by side', key: 'open', len: 150, lines: [{ text: real('open', /bringing it to the front/), effect: 'work-front' }] },
];

let cursor = INTRO;
const STEPS: Step[] = STEP_DEFS.map((s) => {
  const step = { ...s, start: cursor };
  cursor += s.len;
  return step;
});
const OUTRO_START = cursor;
export const DURATION = OUTRO_START + 120;

const TYPE_START = 16;
const CPF = 1.1; // characters typed per frame
const lineAt = (s: Step, i: number) => s.start + TYPE_START + Math.ceil(R[s.key].command.length / CPF) + 14 + i * 26;

// Window state at a frame, from the output lines already shown.
const stateAt = (frame: number) => {
  const st = { workVisible: false, workSigned: false, mainClosed: false, workFront: false, changed: {} as Record<string, number> };
  for (const s of STEPS) {
    s.lines.forEach((l, i) => {
      const at = lineAt(s, i);
      if (!l.effect || frame < at) return;
      if (l.effect === 'work-created') { st.workVisible = true; st.changed.work = at; }
      if (l.effect === 'main-closed') { st.mainClosed = true; st.changed.main = at; }
      if (l.effect === 'work-signed-in') { st.workSigned = true; st.changed.work = at; }
      if (l.effect === 'main-back') { st.mainClosed = false; st.changed.main = at; }
      if (l.effect === 'work-front') { st.workFront = true; st.changed.work = at; }
    });
  }
  return st;
};

const clamp = { extrapolateLeft: 'clamp', extrapolateRight: 'clamp' } as const;

// ---------------------------------------------------------------------------
// Pieces
// ---------------------------------------------------------------------------

const Logo: React.FC<{ size: number; style?: React.CSSProperties }> = ({ size, style }) => (
  <Img src={staticFile('claude.png')} style={{ width: size, height: size, ...style }} />
);

const Dot: React.FC<{ color: string }> = ({ color }) => (
  <div style={{ width: 10, height: 10, borderRadius: 10, background: color }} />
);

const AppWindow: React.FC<{
  account: string;
  tag: string;
  tagColor: string;
  status: 'signed in' | 'closed' | 'not signed in';
  front: boolean;
  enter: number;
  pulse: number;
}> = ({ account, tag, tagColor, status, front, enter, pulse }) => {
  const statusColor = status === 'signed in' ? C.green : status === 'closed' ? C.faint : C.amber;
  const closed = status === 'closed';
  return (
    <div
      style={{
        width: 430,
        height: 268,
        background: C.card,
        borderRadius: 16,
        border: `1px solid ${front ? C.coral : C.line}`,
        boxShadow: front
          ? `0 0 0 4px ${C.coral}33, 0 30px 60px -20px rgba(60,40,20,0.35)`
          : '0 18px 40px -22px rgba(60,40,20,0.30)',
        transform: `translateY(${(1 - enter) * 40 - (front ? 10 : 0)}px) scale(${(0.94 + 0.06 * enter) * (front ? 1.03 : 1)})`,
        opacity: enter * (closed ? 0.45 : 1),
        overflow: 'hidden',
        filter: closed ? 'grayscale(1)' : 'none',
      }}
    >
      <div style={{ height: 36, display: 'flex', alignItems: 'center', gap: 8, padding: '0 14px', borderBottom: `1px solid ${C.line}`, background: '#fbfaf7' }}>
        {['#ff5f57', '#febc2e', '#28c840'].map((c) => (
          <div key={c} style={{ width: 11, height: 11, borderRadius: 11, background: c }} />
        ))}
        <div style={{ flex: 1, textAlign: 'center', fontFamily: SANS, fontSize: 13, fontWeight: 600, color: C.mute, marginRight: 46 }}>Claude</div>
      </div>
      <div style={{ display: 'flex', height: 232 }}>
        <div style={{ width: 92, borderRight: `1px solid ${C.line}`, background: '#faf8f4', padding: '16px 12px', display: 'flex', flexDirection: 'column', gap: 10 }}>
          {[56, 44, 60, 38].map((w, i) => (
            <div key={i} style={{ width: w, height: 8, borderRadius: 4, background: C.line }} />
          ))}
        </div>
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 12 }}>
          <Logo size={64} style={{ transform: `scale(${1 + 0.08 * pulse})` }} />
          <div style={{ fontFamily: SANS, fontSize: 24, fontWeight: 700, color: C.ink }}>{account}</div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontFamily: SANS, fontSize: 15, fontWeight: 600, color: statusColor }}>
            <Dot color={statusColor} />
            {status}
            <span style={{ marginLeft: 6, fontSize: 12, fontWeight: 700, color: tagColor, background: `${tagColor}14`, border: `1px solid ${tagColor}40`, borderRadius: 99, padding: '2px 9px' }}>{tag}</span>
          </div>
        </div>
      </div>
    </div>
  );
};

const colorize = (t: string) => {
  if (t === '…') return <span style={{ color: C.faint }}>…</span>;
  const m = t.match(/^(ok|->) /);
  if (!m) return t;
  return (
    <>
      <span style={{ color: m[1] === 'ok' ? C.green : C.blue, fontWeight: 600 }}>{m[1]}</span>
      {t.slice(m[1].length)}
    </>
  );
};

const Terminal: React.FC<{ frame: number; step: Step }> = ({ frame, step }) => {
  const cmd = R[step.key].command;
  const typed = Math.max(0, Math.min(cmd.length, Math.floor((frame - step.start - TYPE_START) * CPF)));
  const done = typed >= cmd.length;
  const blink = Math.floor(frame / 15) % 2 === 0;
  return (
    <div
      style={{
        width: 980,
        minHeight: 150,
        background: C.card,
        border: `1px solid ${C.line}`,
        borderRadius: 14,
        boxShadow: '0 14px 34px -24px rgba(60,40,20,0.35)',
        padding: '20px 26px',
        fontFamily: MONO,
        fontSize: 17,
        lineHeight: '30px',
        color: C.ink,
        fontVariantLigatures: 'none',
      }}
    >
      <div>
        <span style={{ color: C.coral, fontWeight: 600 }}>$ </span>
        {cmd.slice(0, typed)}
        {(!done || blink) && step.lines.every((_, i) => frame < lineAt(step, i)) && (
          <span style={{ display: 'inline-block', width: 10, height: 20, marginLeft: 2, verticalAlign: -3, background: C.ink }} />
        )}
      </div>
      {step.lines.map((l, i) => {
        const at = lineAt(step, i);
        const a = interpolate(frame - at, [0, 6], [0, 1], clamp);
        return (
          <div key={i} style={{ opacity: a, transform: `translateY(${(1 - a) * 6}px)`, whiteSpace: 'pre-wrap', overflowWrap: 'break-word' }}>
            {colorize(l.text)}
          </div>
        );
      })}
    </div>
  );
};

// ---------------------------------------------------------------------------
// Scenes
// ---------------------------------------------------------------------------

const Intro: React.FC<{ frame: number }> = ({ frame }) => {
  const { fps } = useVideoConfig();
  const pop = spring({ frame, fps, config: { damping: 12, mass: 0.7 } });
  const text = interpolate(frame, [12, 26], [0, 1], clamp);
  const out = interpolate(frame, [INTRO - 14, INTRO], [1, 0], clamp);
  return (
    <AbsoluteFill style={{ alignItems: 'center', justifyContent: 'center', opacity: out }}>
      <Logo size={150} style={{ transform: `scale(${pop})`, filter: 'drop-shadow(0 20px 30px rgba(217,119,87,0.35))' }} />
      <div style={{ fontFamily: SANS, fontWeight: 800, fontSize: 76, letterSpacing: -2.5, color: C.ink, marginTop: 26, opacity: text }}>twindesk</div>
      <div style={{ fontFamily: SANS, fontSize: 28, color: C.mute, marginTop: 6, opacity: text }}>Two Claude accounts, side by side.</div>
    </AbsoluteFill>
  );
};

const Main: React.FC<{ frame: number }> = ({ frame }) => {
  const { fps } = useVideoConfig();
  const step = [...STEPS].reverse().find((s) => frame >= s.start) ?? STEPS[0];
  const st = stateAt(frame);
  const enter1 = spring({ frame: frame - INTRO + 4, fps, config: { damping: 16 } });
  const enter2 = st.workVisible ? spring({ frame: frame - (st.changed.work ?? 0), fps, config: { damping: 15 } }) : 0;
  const pulse = (k: string) => interpolate(frame - (st.changed[k] ?? -99), [0, 6, 18], [0, 1, 0], clamp);
  const titleIn = interpolate(frame - step.start, [0, 12], [0, 1], clamp);
  const outro = frame >= OUTRO_START;
  const termOut = interpolate(frame, [OUTRO_START, OUTRO_START + 12], [1, 0], clamp);
  const outroIn = interpolate(frame, [OUTRO_START + 8, OUTRO_START + 24], [0, 1], clamp);
  const fadeIn = interpolate(frame, [INTRO - 10, INTRO + 4], [0, 1], clamp);
  return (
    <AbsoluteFill style={{ opacity: fadeIn }}>
      {/* step title */}
      <div style={{ position: 'absolute', left: 80, top: 52, display: 'flex', alignItems: 'center', gap: 18, opacity: outro ? termOut : titleIn }}>
        <div style={{ width: 46, height: 46, borderRadius: 46, background: C.coral, color: '#fff', fontFamily: SANS, fontWeight: 800, fontSize: 24, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{step.n}</div>
        <div style={{ fontFamily: SANS, fontWeight: 700, fontSize: 36, letterSpacing: -0.8, color: C.ink }}>{step.title}</div>
      </div>
      <div style={{ position: 'absolute', right: 80, top: 64, display: 'flex', alignItems: 'center', gap: 10, opacity: 0.9 }}>
        <Logo size={26} />
        <div style={{ fontFamily: SANS, fontWeight: 800, fontSize: 22, color: C.ink, letterSpacing: -0.5 }}>twindesk</div>
      </div>
      {/* windows */}
      <div style={{ position: 'absolute', top: outro ? 170 : 138, left: 0, right: 0, display: 'flex', justifyContent: 'center', gap: 56 }}>
        <AppWindow account="Account 1" tag="main" tagColor={C.coral} status={st.mainClosed ? 'closed' : 'signed in'} front={false} enter={enter1} pulse={pulse('main')} />
        <div style={{ opacity: st.workVisible ? 1 : 0.0 }}>
          <AppWindow
            account={st.workSigned ? 'Account 2' : 'Profile "work"'}
            tag="work"
            tagColor={C.blue}
            status={st.workSigned ? 'signed in' : 'not signed in'}
            front={st.workFront}
            enter={enter2}
            pulse={pulse('work')}
          />
        </div>
      </div>
      {/* terminal */}
      <div style={{ position: 'absolute', top: 452, left: 0, right: 0, display: 'flex', justifyContent: 'center', opacity: termOut }}>
        <Terminal frame={frame} step={step} />
      </div>
      {/* outro */}
      {outro && (
        <div style={{ position: 'absolute', top: 486, left: 0, right: 0, display: 'flex', flexDirection: 'column', alignItems: 'center', opacity: outroIn }}>
          <div style={{ fontFamily: MONO, fontSize: 21, color: C.ink, background: C.card, border: `1px solid ${C.line}`, borderRadius: 12, padding: '14px 24px', boxShadow: '0 14px 34px -24px rgba(60,40,20,0.35)' }}>
            <span style={{ color: C.coral, fontWeight: 600 }}>$ </span>brew install MartinFerret/twindesk/twindesk
          </div>
          <div style={{ fontFamily: SANS, fontSize: 15, color: C.mute, marginTop: 22 }}>Open source · MIT · github.com/MartinFerret/twindesk</div>
          <div style={{ fontFamily: SANS, fontSize: 13, color: C.faint, marginTop: 8 }}>
            Real output, recorded on macOS 26.2 with Claude Desktop 3.6556.2. Not affiliated with Anthropic.
          </div>
        </div>
      )}
    </AbsoluteFill>
  );
};

export const Demo: React.FC = () => {
  const frame = useCurrentFrame();
  return (
    <AbsoluteFill style={{ background: C.bg }}>
      <AbsoluteFill style={{ background: `radial-gradient(900px 500px at 50% -10%, ${C.coral}1a, transparent 70%)` }} />
      {frame < INTRO && <Intro frame={frame} />}
      {frame >= INTRO - 10 && <Main frame={frame} />}
    </AbsoluteFill>
  );
};
