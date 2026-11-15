import type { CSSProperties } from 'react';

export type Color = 'blue' | 'pink' | 'amber' | 'violet' | 'teal';

/** The app's session robot, drawn in CSS with the same proportions as the Swift avatar. */
export function Bot({ c, mood, u }: { c: Color; mood?: 'alert' | 'sleepy'; u?: number }) {
  const style = { '--c': `var(--${c})`, ...(u ? { '--u': `${u}px` } : {}) } as CSSProperties;
  return (
    <span className={`bot ${mood ?? ''}`} style={style} aria-hidden="true">
      <span className="f" />
      <span className="m" />
    </span>
  );
}
