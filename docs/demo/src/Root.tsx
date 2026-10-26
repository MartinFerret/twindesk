import { Composition, Still } from 'remotion';
import { Demo, DURATION, FPS } from './Demo';
import { Social } from './Social';

export const Root = () => (
  <>
    <Composition id="Demo" component={Demo} durationInFrames={DURATION} fps={FPS} width={1280} height={720} />
    <Still id="Social" component={Social} width={1280} height={640} />
  </>
);
