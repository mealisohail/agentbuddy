'use client';
import { useRef, useState } from 'react';

export function CopyCommand({ cmd }: { cmd: string }) {
  const [label, setLabel] = useState('Copy');
  const code = useRef<HTMLSpanElement>(null);
  async function copy() {
    try {
      await navigator.clipboard.writeText(cmd);
      setLabel('Copied');
    } catch {
      if (code.current) getSelection()?.selectAllChildren(code.current);
      setLabel('Press ⌘C');
    }
    setTimeout(() => setLabel('Copy'), 1800);
  }
  return (
    <div className="term">
      <code><span className="p">$ </span><span ref={code}>{cmd}</span></code>
      <button className="copy" type="button" onClick={copy} aria-label={`Copy command: ${cmd}`}>{label}</button>
    </div>
  );
}
