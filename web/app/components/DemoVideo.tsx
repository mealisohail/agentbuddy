'use client';
import { useEffect, useRef, useState } from 'react';
import { VIDEO_FALLBACK } from '../site';

const CHAPTERS = [
  { t: 0, label: 'Five sessions' },
  { t: 3, label: 'Lives in the notch' },
  { t: 6, label: 'Who needs you' },
  { t: 10, label: 'Allow from the notch' },
  { t: 13.5, label: 'Every step, live' },
  { t: 16, label: 'Get it' },
];

/** The demo on a laptop whose notch lines up with the one drawn in the video. Plays silently once on screen. */
export function DemoVideo() {
  const video = useRef<HTMLVideoElement>(null);
  const userPaused = useRef(false);
  const [time, setTime] = useState(0);
  const [withSound, setWithSound] = useState(false);

  useEffect(() => {
    const v = video.current!;
    v.muted = true;   // React doesn't put `muted` in the server HTML, and browsers only autoplay muted video
    const reduce = matchMedia('(prefers-reduced-motion: reduce)').matches;
    const io = new IntersectionObserver(([e]) => {
      if (e.isIntersecting && !userPaused.current && !reduce) v.play().catch(() => {});
      else if (!e.isIntersecting) v.pause();
    }, { threshold: 0.5 });
    io.observe(v);
    return () => io.disconnect();
  }, []);

  const play = () => { userPaused.current = false; video.current?.play().catch(() => {}); };
  const duration = video.current?.duration || 20;

  return (
    <div className="film">
      <div className="laptop">
        <div className="screen">
          <video id="demo" ref={video} muted={!withSound} loop={!withSound} controls={withSound} playsInline preload="metadata" poster="/demo.jpg"
            aria-label="20-second demo of AgentBuddy" onTimeUpdate={e => setTime(e.currentTarget.currentTime)}
            onClick={() => {
              const v = video.current!;
              if (withSound) return;
              if (v.paused) play(); else { userPaused.current = true; v.pause(); }
            }}>
            <source src="/demo.mp4" type="video/mp4" />
            <source src={VIDEO_FALLBACK} type="video/mp4" />
          </video>
          <div className="notch" />
          {!withSound && (
            <button className="sound" type="button" onClick={() => {
              const v = video.current!;
              v.muted = false; v.currentTime = 0; setWithSound(true); play();
            }}>Play with sound</button>
          )}
        </div>
      </div>
      <div className="base" />
      <ol className="chapters" aria-label="Jump to a part of the demo">
        {CHAPTERS.map((c, k) => {
          const end = CHAPTERS[k + 1]?.t ?? duration;
          const on = time >= c.t && time < end;
          return (
            <li key={c.t}>
              <button type="button" aria-current={on} onClick={() => { video.current!.currentTime = c.t; play(); }}>
                {c.label}<span style={{ width: on ? `${((time - c.t) / (end - c.t)) * 100}%` : 0 }} />
              </button>
            </li>
          );
        })}
      </ol>
    </div>
  );
}
