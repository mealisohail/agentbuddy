'use client';
import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from 'react';
import { Bot, type Color } from './Bot';

type Event = { c: Color; title: string; status: string; done?: boolean; body: (answer: (a: string) => void) => ReactNode };

// The same moments the app has, answered by the visitor.
const EVENTS: Event[] = [
  {
    c: 'blue', title: 'Release v2.4 notes', status: 'needs permission',
    body: answer => (<>
      <div className="cmd">Bash: ./scripts/release.sh --tag v2.4.0</div>
      <div className="btns">
        <button className="btn lime" onClick={() => answer('Allowed')}>Allow</button>
        <button className="btn" onClick={() => answer('Denied')}>Deny</button>
        <button className="btn" onClick={() => answer('Handed back to Claude')}>In Terminal</button>
      </div>
    </>),
  },
  {
    c: 'pink', title: 'Pick a chart library', status: 'asks a question',
    body: answer => (<>
      <div className="q">Which chart library should I use?</div>
      <div className="opts">
        {[['Recharts', 'React-first'], ['ECharts', 'Huge feature set'], ['Visx', 'Low-level']].map(([n, d]) => (
          <button key={n} className="opt" onClick={() => answer(`Answered ${n}`)}>{n}<small>{d}</small></button>
        ))}
      </div>
    </>),
  },
  { c: 'amber', title: 'Fix coupon rounding bug', status: 'Done in 2m 14s, 6 tools', done: true, body: () => <div className="result">All 42 tests passed</div> },
];

export function LiveIsland() {
  const [stage, setStage] = useState<'notch' | 'pill' | 'open'>('notch');
  const [i, setI] = useState(0);
  const [answered, setAnswered] = useState<string | null>(null);
  const [height, setHeight] = useState(0);
  const card = useRef<HTMLDivElement>(null);
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined);
  const reduce = useRef(false);
  const e = EVENTS[i % EVENTS.length];
  const later = (ms: number, f: () => void) => { clearTimeout(timer.current); timer.current = setTimeout(f, reduce.current ? 0 : ms); };

  // notch → pill → first request
  useEffect(() => {
    reduce.current = matchMedia('(prefers-reduced-motion: reduce)').matches;
    const a = setTimeout(() => setStage('pill'), reduce.current ? 0 : 350);
    const b = setTimeout(() => setStage('open'), reduce.current ? 0 : 1100);
    return () => { clearTimeout(a); clearTimeout(b); clearTimeout(timer.current); };
  }, []);

  // the island's height follows the card, which reflows while the island widens
  useLayoutEffect(() => {
    const el = card.current!;
    const ro = new ResizeObserver(() => setHeight(el.offsetHeight + 30));
    ro.observe(el);
    return () => ro.disconnect();
  }, []);

  // a finished session only shows briefly
  useEffect(() => { if (stage === 'open' && e.done) later(3200, next); }, [stage, i]); // eslint-disable-line react-hooks/exhaustive-deps

  function next() {
    setStage('pill');
    later(1300, () => { setAnswered(null); setI(n => n + 1); later(500, () => setStage('open')); });
  }
  function answer(a: string) { setAnswered(a); later(1100, next); }

  const waiting = stage !== 'notch' && !e.done && !answered;
  return (
    <div className="island-zone">
      <div className={`island ${stage === 'notch' ? '' : 'pill'} ${stage === 'open' ? 'open' : ''}`}
        style={stage === 'open' ? { height } : undefined} role="region" aria-label="Live AgentBuddy demo" aria-live="polite">
        <div className="pillrow" aria-hidden="true">
          <Bot c="blue" /><Bot c="pink" /><Bot c="amber" />
          <span className="more">+2</span>
          <span className="count" data-n={waiting ? 1 : 0}><i /><span>{waiting ? 1 : 0}</span></span>
        </div>
        <div className="card" ref={card} inert={stage !== 'open'}>
          <div className="card-head">
            <Bot c={e.c} mood={e.done ? undefined : 'alert'} />
            <div><b>{e.title}</b><span className={`st ${e.done ? 'done' : ''}`}>{e.status}</span></div>
          </div>
          <div className={`card-body ${answered || e.done ? 'quiet' : ''}`}>
            {answered ? <div className="result">✓ {answered}</div> : e.body(answer)}
          </div>
        </div>
      </div>
      <p className={`hint ${stage === 'open' && i < 2 && !e.done ? 'on' : ''}`}>This is the real flow. Go ahead, answer it.</p>
    </div>
  );
}
