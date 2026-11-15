import Image from 'next/image';
import type { CSSProperties, ReactNode } from 'react';
import { Bot, type Color } from './components/Bot';
import { CopyCommand } from './components/CopyCommand';
import { DemoVideo } from './components/DemoVideo';
import { InstallTabs } from './components/InstallTabs';
import { LiveIsland } from './components/LiveIsland';
import { INSTALL, REPO } from './site';

const dot = (c: Color | 'lime') => ({ '--c': `var(--${c})` }) as CSSProperties;

function Feature({ bot, title, intro, children, stage }: { bot: ReactNode; title: string; intro: string; children: ReactNode; stage: ReactNode }) {
  return (
    <section className="feat">
      <div className="copytext">
        {bot}
        <h3>{title}</h3>
        <p>{intro}</p>
        {children}
      </div>
      {stage}
    </section>
  );
}

const shot = (src: string, w: number, h: number, alt: string) => (
  <Image src={src} width={w} height={h} alt={alt} sizes="(max-width: 860px) 90vw, 460px" />
);

export default function Home() {
  return (
    <>
      <header className="hero">
        <LiveIsland />
        <div className="wrap">
          <h1>Every Claude<br /> Code session,<br /> in your notch.</h1>
          <p className="lede">AgentBuddy is a free Mac app that shows which sessions are working, which are done and which need you. Answer them right from the notch, without hunting for the window.</p>
          <div className="get">
            <CopyCommand cmd={INSTALL} />
            <p className="alt">Paste it into Terminal. Prefer something else? <a href="#install">Homebrew or a manual download</a>.</p>
          </div>
        </div>
        <DemoVideo />
      </header>

      <main className="features wrap" id="features">
        <h2 className="sec-title">Run five sessions. Keep one eye on all of them.</h2>
        <p className="sec-intro">Claude Code is happy to work in parallel. Keeping track of it shouldn&apos;t mean cycling through terminal tabs to find the one that&apos;s been waiting on you for ten minutes.</p>

        <Feature bot={<Bot c="blue" mood="alert" u={1.4} />} title="Answer without switching windows"
          intro="When a session asks for permission or asks you a question, the island drops down with the card. One click and Claude carries on."
          stage={<div className="stage" style={{ '--tint': '#D7E3FB' } as CSSProperties}>{shot('/site/needs-you.png', 920, 1225, 'AgentBuddy showing a permission request with Allow and Deny, and a multiple-choice question')}</div>}>
          <ul>
            <li style={dot('blue')}><b>Allow or Deny</b> commands, edits and anything else Claude asks permission for.</li>
            <li style={dot('pink')}><b>Pick an answer</b> to Claude&apos;s multiple-choice questions, or type your own.</li>
            <li style={dot('amber')}><b>Hand it back</b> to Claude&apos;s own prompt with one click when you want &ldquo;always allow&rdquo;.</li>
            <li style={dot('violet')}><b>Stays quiet</b> if you&apos;re already looking at that session, and speaks up when you look away.</li>
          </ul>
        </Feature>

        <Feature bot={<Bot c="amber" u={1.4} />} title="See who's working, who's done and who needs you"
          intro="Sessions sort themselves. The ones waiting on you come first with a lime ring, working ones show what they're doing right now, and finished ones fade back."
          stage={<div className="stage" style={{ '--tint': '#FBE3CC' } as CSSProperties}>{shot('/site/sorted.png', 920, 624, 'Working sessions with live activity and progress ticks, and an idle session below')}</div>}>
          <ul>
            <li style={dot('amber')}><b>Live activity</b> like &ldquo;Run unit tests&rdquo; or &ldquo;Edit coupon.ts&rdquo;, straight from the session.</li>
            <li style={dot('teal')}><b>Honest progress.</b> One tick per tool call, failures in red, and a real 3/5 only when Claude keeps a todo list.</li>
            <li style={dot('pink')}><b>A chime</b> when a session needs you and a soft tick when one finishes. Mute it any time.</li>
          </ul>
        </Feature>

        <Feature bot={<Bot c="violet" u={1.4} />} title="Open any session to follow along"
          intro="Click a session to see its prompt, every step it took and the command it's running, without leaving what you're doing."
          stage={<div className="stage" style={{ '--tint': '#E6DCFB' } as CSSProperties}>{shot('/site/detail.png', 920, 1030, 'Session detail with each step, the running command and a message box')}</div>}>
          <ul>
            <li style={dot('violet')}><b>Send a message</b> to a Terminal, iTerm2 or tmux session from the island. In VS Code, AgentBuddy copies it and opens the window.</li>
            <li style={dot('blue')}><b>Jump to it.</b> One click opens the exact Terminal or iTerm tab, or the VS Code window for that folder.</li>
          </ul>
        </Feature>

        <Feature bot={<Bot c="teal" mood="sleepy" u={1.4} />} title="Finds every session on its own"
          intro="Start Claude Code anywhere and it shows up. There's nothing to set up per project."
          stage={
            <div className="stage bare" style={{ '--tint': '#CDEFEC' } as CSSProperties}>
              <div className="mini" aria-hidden="true">
                <div className="island pill">
                  <div className="pillrow">
                    <Bot c="blue" /><Bot c="pink" /><Bot c="amber" /><Bot c="violet" /><Bot c="teal" mood="sleepy" />
                    <span className="count" data-n="2"><i /><span>2</span></span>
                  </div>
                </div>
              </div>
              <div className="hosts" aria-hidden="true">
                {([['blue', 'alert', 'Terminal'], ['pink', 'alert', 'iTerm2'], ['amber', undefined, 'tmux'], ['violet', undefined, 'VS Code'], ['teal', 'sleepy', 'Cursor']] as const)
                  .map(([c, m, n]) => <div key={n}><Bot c={c} mood={m} />{n}</div>)}
              </div>
            </div>
          }>
          <ul>
            <li style={dot('teal')}><b>Works with</b> Terminal, iTerm2, tmux, VS Code and Cursor.</li>
            <li style={dot('violet')}><b>oh-my-pi too.</b> Its <code>omp</code> sessions show up alongside Claude Code, with every step. Approvals stay in omp&apos;s own prompt, one click away.</li>
          </ul>
        </Feature>

        <div className="small">
          <div><h4><Bot c="blue" />Stays on your Mac</h4><p>AgentBuddy reads Claude Code&apos;s local session files and makes no network requests.</p></div>
          <div><h4><Bot c="pink" />Out of the way</h4><p>Hover the notch to open it. Move away, click elsewhere or press Esc to close it.</p></div>
          <div><h4><Bot c="amber" />No notch, no problem</h4><p>On Macs without a notch it hangs just under the menu bar instead.</p></div>
        </div>
      </main>

      <section className="setup" id="install" aria-labelledby="install-title">
        <div className="wrap">
          <h2 className="sec-title" id="install-title">Install in one line</h2>
          <p className="sec-intro">Free and open source. Nothing needs sudo, and the installer is short enough to read first.</p>
          <InstallTabs />
          <ol className="steps">
            <li><h3>Install</h3><p>Use any of the options above. The robot appears in your menu bar and the island around your notch.</p></li>
            <li><h3>Turn on answers</h3><p>Click Enable in the island. It adds one hook to <code>~/.claude/settings.json</code>, keeps everything else in that file and saves a backup next to it.</p></li>
            <li><h3>Restart your sessions</h3><p>Running Claude Code sessions pick up the hook after a restart. Watching sessions works without this step.</p></li>
          </ol>
          <p className="req"><b>Needs macOS 14 Sonoma or newer</b>, on Apple Silicon or Intel. If AgentBuddy isn&apos;t running, Claude Code simply asks in its own prompt as usual.</p>
        </div>
      </section>

      <footer>
        <div className="wrap">
          <span className="brand"><Image src="/site/icon.png" alt="" width={34} height={34} />AgentBuddy</span>
          <span>MIT licensed. <a href={REPO}>Source on GitHub</a> and <a href={`${REPO}/issues`}>report an issue</a>.</span>
        </div>
      </footer>
    </>
  );
}
