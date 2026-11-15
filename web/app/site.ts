// Set NEXT_PUBLIC_SITE_URL in Vercel once you have a custom domain; canonical URLs, the sitemap and social cards use it.
export const SITE_URL = (
  process.env.NEXT_PUBLIC_SITE_URL ??
  (process.env.VERCEL_PROJECT_PRODUCTION_URL ? `https://${process.env.VERCEL_PROJECT_PRODUCTION_URL}` : 'http://localhost:3000')
).replace(/\/$/, '');

export const REPO = 'https://github.com/mealisohail/agentbuddy';
export const INSTALL = 'curl -fsSL https://raw.githubusercontent.com/mealisohail/agentbuddy/main/install.sh | sh';
export const DOWNLOAD = `${REPO}/releases/latest/download/AgentBuddy.zip`;
export const VIDEO_FALLBACK = 'https://github.com/user-attachments/assets/2746defc-757a-4786-b602-9ba82e77acd1';

export const TITLE = 'AgentBuddy: every Claude Code session in your Mac notch';
export const DESCRIPTION =
  "A free, open-source Mac app that shows all your Claude Code sessions in the notch. See who's working, who's done and who needs you, then Allow, Deny or answer without switching windows.";
