import type { MetadataRoute } from 'next';

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: 'AgentBuddy',
    short_name: 'AgentBuddy',
    description: 'Every Claude Code session, in your Mac notch.',
    start_url: '/',
    display: 'browser',
    background_color: '#ECEEF2',
    theme_color: '#ECEEF2',
    icons: [{ src: '/icon.png', sizes: '512x512', type: 'image/png' }],
  };
}
