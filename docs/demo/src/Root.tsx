import { Composition } from 'remotion';
import { Demo, DURATION, FPS } from './Demo';

export const Root = () => (
  <Composition id="Demo" component={Demo} durationInFrames={DURATION} fps={FPS} width={1280} height={720} />
);
