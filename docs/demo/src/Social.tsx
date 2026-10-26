import React from 'react';
import { AbsoluteFill } from 'remotion';
import { loadFont as loadMono } from '@remotion/google-fonts/JetBrainsMono';
import { loadFont as loadSans } from '@remotion/google-fonts/Inter';
import rec from './recordings.json';

// Social preview card (1280x640). The terminal lines are real output from
// recordings/login.txt.

const { fontFamily: MONO } = loadMono('normal', { weights: ['400', '700'], subsets: ['latin'] });
const { fontFamily: SANS } = loadSans('normal', { weights: ['400', '600', '800'], subsets: ['latin'] });

const coral = '#d97757';
const violet = '#a78bfa';
const edge = '#232733';

const login = (rec as Record<string, { command: string; output: string[] }>).login;
const pick = (re: RegExp) => login.output.find((l) => re.test(l)) ?? '';
const lines = [
  pick(/main instance stopped/),
  pick(/profile 'work' is signed in/),
  pick(/main instance running again/),
  pick(/profile 'work' running \(PID/),
];

const Badge: React.FC<{ color: string; label: string; title: string; sub: string }> = ({ color, label, title, sub }) => (
  <div style={{ display: 'flex', alignItems: 'center', gap: 14, background: '#12141b', border: `1px solid ${edge}`, borderRadius: 16, padding: '14px 18px', width: 250 }}>
    <div style={{ width: 44, height: 44, borderRadius: 12, background: color, color: '#0b0b0f', fontFamily: SANS, fontWeight: 800, fontSize: 24, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>{label}</div>
    <div>
      <div style={{ fontFamily: SANS, fontWeight: 600, fontSize: 19, color: '#fff' }}>{title}</div>
      <div style={{ fontFamily: SANS, fontSize: 14, color: '#4ade80' }}>{sub}</div>
    </div>
  </div>
);

export const Social: React.FC = () => (
  <AbsoluteFill style={{ background: '#0a0b0f', padding: '64px 72px' }}>
    <AbsoluteFill style={{ background: `radial-gradient(800px 420px at 12% 0%, ${coral}2b, transparent 60%), radial-gradient(700px 420px at 100% 100%, ${violet}24, transparent 60%)` }} />
    <div style={{ position: 'relative', display: 'flex', height: '100%', gap: 48 }}>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center' }}>
        <div style={{ fontFamily: SANS, fontWeight: 800, fontSize: 104, letterSpacing: -4, color: '#fff', lineHeight: 1 }}>twindesk</div>
        <div style={{ fontFamily: SANS, fontSize: 34, color: '#c9cdd6', marginTop: 18, lineHeight: 1.25 }}>
          Several Claude Desktop accounts,
          <br />
          side by side.
        </div>
        <div style={{ fontFamily: SANS, fontSize: 19, color: '#7c8496', marginTop: 28 }}>Open source · MIT · No sudo · No telemetry · macOS tested</div>
        <div style={{ fontFamily: SANS, fontSize: 15, color: '#565d6e', marginTop: 34 }}>Unofficial. Not affiliated with Anthropic.</div>
      </div>
      <div style={{ width: 520, display: 'flex', flexDirection: 'column', justifyContent: 'center', gap: 16 }}>
        <Badge color={coral} label="1" title="Claude" sub="signed in · account 1" />
        <div style={{ marginLeft: 60 }}>
          <Badge color={violet} label="2" title="work" sub="signed in · account 2" />
        </div>
        <div style={{ marginTop: 10, background: '#12141b', border: `1px solid ${edge}`, borderRadius: 14, padding: '16px 18px', fontFamily: MONO, fontSize: 13.5, lineHeight: '23px', color: '#d9dde6', fontVariantLigatures: 'none' }}>
          <div>
            <span style={{ color: coral, fontWeight: 700 }}>❯ </span>
            {login.command}
          </div>
          {lines.map((l) => (
            <div key={l}>
              <span style={{ color: '#4ade80', fontWeight: 700 }}>ok</span>
              {l.replace(/^ok/, '')}
            </div>
          ))}
        </div>
      </div>
    </div>
  </AbsoluteFill>
);
