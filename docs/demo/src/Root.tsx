import { Composition, Still } from 'remotion';
import { Demo, DURATION, FPS } from './Demo';
import { Social } from './Social';
import { LinkedIn } from './LinkedIn';

export const Root = () => (
  <>
    <Composition id="Demo" component={Demo} durationInFrames={DURATION} fps={FPS} width={1280} height={720} />
    <Still id="Social" component={Social} width={1280} height={640} />
    <Still id="LinkedIn" component={LinkedIn} width={1200} height={1500} defaultProps={{ lang: 'en' as const }} />
  </>
);
