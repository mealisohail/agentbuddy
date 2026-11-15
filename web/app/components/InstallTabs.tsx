'use client';
import { useRef, useState, type KeyboardEvent } from 'react';
import { CopyCommand } from './CopyCommand';
import { DOWNLOAD, INSTALL } from '../site';

const TABS = ['One line', 'Homebrew', 'Download'] as const;

export function InstallTabs() {
  const [tab, setTab] = useState(0);
  const refs = useRef<(HTMLButtonElement | null)[]>([]);
  function move(e: KeyboardEvent, i: number) {
    const d = e.key === 'ArrowRight' ? 1 : e.key === 'ArrowLeft' ? -1 : 0;
    if (!d) return;
    const n = (i + d + TABS.length) % TABS.length;
    setTab(n);
    refs.current[n]?.focus();
  }
  return (
    <>
      <div className="tabs" role="tablist" aria-label="Install method">
        {TABS.map((t, i) => (
          <button key={t} ref={el => { refs.current[i] = el; }} className="tab" role="tab" id={`t-${i}`} aria-controls={`p-${i}`}
            aria-selected={tab === i} tabIndex={tab === i ? 0 : -1} onClick={() => setTab(i)} onKeyDown={e => move(e, i)}>{t}</button>
        ))}
      </div>
      <div className="panel" role="tabpanel" id="p-0" aria-labelledby="t-0" hidden={tab !== 0}>
        <CopyCommand cmd={INSTALL} />
        <p>Installs AgentBuddy into <code>~/Applications</code> and opens it. Run it again any time to update.</p>
      </div>
      <div className="panel" role="tabpanel" id="p-1" aria-labelledby="t-1" hidden={tab !== 1}>
        <CopyCommand cmd="brew tap mealisohail/agentbuddy https://github.com/mealisohail/agentbuddy && brew trust mealisohail/agentbuddy && brew install --cask agentbuddy" />
        <p>Updates come with <code>brew upgrade --cask agentbuddy</code>.</p>
      </div>
      <div className="panel" role="tabpanel" id="p-2" aria-labelledby="t-2" hidden={tab !== 2}>
        <div className="btns"><a className="btn lime" href={DOWNLOAD}>Download AgentBuddy.zip</a></div>
        <p>Unzip it, move AgentBuddy to Applications, then right-click it and choose Open the first time. AgentBuddy isn&apos;t notarized by Apple, because that needs a paid developer account, so macOS asks once. The one-line and Homebrew installs skip this step.</p>
      </div>
    </>
  );
}
