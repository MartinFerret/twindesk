import React from 'react';
import { AbsoluteFill, Img, staticFile } from 'remotion';
import { loadFont as loadMono } from '@remotion/google-fonts/JetBrainsMono';
import { loadFont as loadSans } from '@remotion/google-fonts/Inter';

// Portrait post image (1200x1500, 4:5). Same identity as the demo video.

const { fontFamily: MONO } = loadMono('normal', { weights: ['400', '600'], subsets: ['latin'] });
const { fontFamily: SANS } = loadSans('normal', { weights: ['400', '500', '600', '700', '800'], subsets: ['latin'] });

const C = {
  bg: '#f5f3ee',
  ink: '#1f1e1d',
  mute: '#6f6b64',
  faint: '#a9a49b',
  line: '#e5e1d8',
  card: '#ffffff',
  coral: '#d97757',
  green: '#2f8a4c',
  blue: '#3b5bdb',
};

const TEXT = {
  en: {
    title: ['Two Claude accounts.', 'Side by side.'],
    sub: 'No more signing out to switch.',
    acc1: 'Personal',
    acc2: 'Work',
    signed: 'signed in',
    steps: [
      ['twindesk add work', 'Create a profile'],
      ['twindesk login work', 'Sign in once'],
      ['twindesk open work', 'Open it next to your Claude'],
    ],
    foot: 'Free and open source',
    install: 'Install',
    legal: 'macOS · Not affiliated with Anthropic',
  },
  fr: {
    title: ['Deux comptes Claude.', 'Côte à côte.'],
    sub: 'Fini la déconnexion pour changer de compte.',
    acc1: 'Perso',
    acc2: 'Pro',
    signed: 'connecté',
    steps: [
      ['twindesk add work', 'Créer un profil'],
      ['twindesk login work', 'Se connecter une fois'],
      ['twindesk open work', "L'ouvrir à côté de votre Claude"],
    ],
    foot: 'Gratuit et open source',
    install: 'Installer',
    legal: 'macOS · Non affilié à Anthropic',
  },
};

const Logo: React.FC<{ size: number }> = ({ size }) => <Img src={staticFile('claude.png')} style={{ width: size, height: size }} />;

const Win: React.FC<{ name: string; tag: string; color: string; signed: string; tilt: number }> = ({ name, tag, color, signed, tilt }) => (
  <div
    style={{
      width: 490,
      height: 330,
      background: C.card,
      borderRadius: 22,
      border: `1px solid ${C.line}`,
      boxShadow: '0 30px 60px -28px rgba(60,40,20,0.35)',
      overflow: 'hidden',
      transform: `rotate(${tilt}deg)`,
    }}
  >
    <div style={{ height: 46, display: 'flex', alignItems: 'center', gap: 10, padding: '0 18px', borderBottom: `1px solid ${C.line}`, background: '#fbfaf7' }}>
      {['#ff5f57', '#febc2e', '#28c840'].map((c) => (
        <div key={c} style={{ width: 14, height: 14, borderRadius: 14, background: c }} />
      ))}
      <div style={{ flex: 1, textAlign: 'center', fontFamily: SANS, fontSize: 16, fontWeight: 600, color: C.mute, marginRight: 60 }}>Claude</div>
    </div>
    <div style={{ display: 'flex', height: 284 }}>
      <div style={{ width: 104, borderRight: `1px solid ${C.line}`, background: '#faf8f4', padding: '22px 16px', display: 'flex', flexDirection: 'column', gap: 13 }}>
        {[62, 48, 68, 40].map((w, i) => (
          <div key={i} style={{ width: w, height: 10, borderRadius: 5, background: C.line }} />
        ))}
      </div>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', gap: 14 }}>
        <Logo size={84} />
        <div style={{ fontFamily: SANS, fontSize: 34, fontWeight: 800, color: C.ink, letterSpacing: -0.6 }}>{name}</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, fontFamily: SANS, fontSize: 19, fontWeight: 600, color: C.green }}>
          <div style={{ width: 11, height: 11, borderRadius: 11, background: C.green }} />
          {signed}
          <span style={{ marginLeft: 4, fontSize: 15, fontWeight: 700, color, background: `${color}14`, border: `1px solid ${color}40`, borderRadius: 99, padding: '3px 12px' }}>{tag}</span>
        </div>
      </div>
    </div>
  </div>
);

export const LinkedIn: React.FC<{ lang: 'en' | 'fr' }> = ({ lang }) => {
  const t = TEXT[lang];
  return (
    <AbsoluteFill style={{ background: C.bg, fontFamily: SANS }}>
      <AbsoluteFill style={{ background: `radial-gradient(1000px 600px at 50% 0%, ${C.coral}24, transparent 70%)` }} />
      <div style={{ position: 'relative', display: 'flex', flexDirection: 'column', alignItems: 'center', height: '100%', padding: '84px 70px 64px' }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
          <Logo size={46} />
          <div style={{ fontSize: 34, fontWeight: 800, color: C.ink, letterSpacing: -0.8 }}>twindesk</div>
        </div>
        <div style={{ marginTop: 46, textAlign: 'center', fontSize: 86, fontWeight: 800, letterSpacing: -3.2, lineHeight: 1.04, color: C.ink }}>
          {t.title[0]}
          <br />
          <span style={{ color: C.coral }}>{t.title[1]}</span>
        </div>
        <div style={{ marginTop: 22, fontSize: 32, color: C.mute }}>{t.sub}</div>

        <div style={{ marginTop: 64, display: 'flex', gap: 40 }}>
          <Win name={t.acc1} tag="main" color={C.coral} signed={t.signed} tilt={-1.5} />
          <Win name={t.acc2} tag="work" color={C.blue} signed={t.signed} tilt={1.5} />
        </div>

        <div style={{ marginTop: 66, width: 1020, background: C.card, border: `1px solid ${C.line}`, borderRadius: 22, boxShadow: '0 18px 40px -30px rgba(60,40,20,0.35)', padding: '14px 34px' }}>
          {t.steps.map(([cmd, label], i) => (
            <div key={cmd} style={{ display: 'flex', alignItems: 'center', gap: 22, padding: '20px 0', borderTop: i ? `1px solid ${C.line}` : 'none' }}>
              <div style={{ width: 48, height: 48, borderRadius: 48, background: C.coral, color: '#fff', fontWeight: 800, fontSize: 24, display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>{i + 1}</div>
              <div style={{ fontFamily: MONO, fontSize: 27, color: C.ink, width: 420, fontVariantLigatures: 'none' }}>{cmd}</div>
              <div style={{ fontSize: 27, color: C.mute, fontWeight: 500 }}>{label}</div>
            </div>
          ))}
        </div>

        <div style={{ marginTop: 44, display: 'flex', alignItems: 'center', gap: 18 }}>
          <div style={{ fontSize: 24, fontWeight: 600, color: C.mute }}>{t.install}</div>
          <div style={{ fontFamily: MONO, fontSize: 25, color: '#fff', background: C.ink, borderRadius: 14, padding: '16px 26px', fontVariantLigatures: 'none' }}>
            <span style={{ color: C.coral }}>$ </span>brew install MartinFerret/twindesk/twindesk
          </div>
        </div>

        <div style={{ marginTop: 'auto', display: 'flex', flexDirection: 'column', alignItems: 'center', gap: 12 }}>
          <div style={{ fontSize: 26, fontWeight: 700, color: C.ink }}>
            {t.foot} · <span style={{ color: C.coral }}>github.com/MartinFerret/twindesk</span>
          </div>
          <div style={{ fontSize: 17, color: C.faint }}>{t.legal}</div>
        </div>
      </div>
    </AbsoluteFill>
  );
};
