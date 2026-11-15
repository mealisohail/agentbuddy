import type { Metadata, Viewport } from 'next';
import { Gabarito, JetBrains_Mono } from 'next/font/google';
import { DESCRIPTION, REPO, SITE_URL, TITLE } from './site';
import './globals.css';

const gabarito = Gabarito({ subsets: ['latin'], weight: ['400', '500', '600', '700', '800', '900'], variable: '--font-gabarito' });
const mono = JetBrains_Mono({ subsets: ['latin'], weight: ['500'], variable: '--font-mono' });

export const metadata: Metadata = {
  metadataBase: new URL(SITE_URL),
  title: TITLE,
  description: DESCRIPTION,
  applicationName: 'AgentBuddy',
  keywords: [
    'Claude Code', 'Claude Code sessions', 'Mac notch app', 'macOS menu bar app', 'AI coding agent monitor',
    'Claude Code permissions', 'Dynamic Island for Mac', 'parallel Claude Code', 'AgentBuddy',
  ],
  authors: [{ name: 'Sohail Akhtar Ali', url: REPO }],
  creator: 'Sohail Akhtar Ali',
  category: 'developer tools',
  alternates: { canonical: '/' },
  openGraph: {
    type: 'website',
    url: '/',
    siteName: 'AgentBuddy',
    title: TITLE,
    description: DESCRIPTION,
    locale: 'en_US',
    videos: [{ url: `${SITE_URL}/demo.mp4`, type: 'video/mp4', width: 1920, height: 1080 }],
  },
  twitter: { card: 'summary_large_image', title: TITLE, description: DESCRIPTION },
  robots: { index: true, follow: true, googleBot: { index: true, follow: true, 'max-image-preview': 'large', 'max-video-preview': -1 } },
};

export const viewport: Viewport = { themeColor: '#ECEEF2', colorScheme: 'light' };

// Structured data so search engines can show it as a free macOS app with its demo video.
const jsonLd = {
  '@context': 'https://schema.org',
  '@graph': [
    {
      '@type': 'SoftwareApplication',
      name: 'AgentBuddy',
      description: DESCRIPTION,
      url: SITE_URL,
      applicationCategory: 'DeveloperApplication',
      operatingSystem: 'macOS 14 or later',
      offers: { '@type': 'Offer', price: '0', priceCurrency: 'USD' },
      downloadUrl: `${REPO}/releases/latest`,
      softwareVersion: '1.0.0',
      license: 'https://opensource.org/licenses/MIT',
      image: `${SITE_URL}/opengraph-image.png`,
      screenshot: [`${SITE_URL}/site/needs-you.png`, `${SITE_URL}/site/detail.png`],
      codeRepository: REPO,
    },
    {
      '@type': 'VideoObject',
      name: 'AgentBuddy in 20 seconds',
      description: 'How AgentBuddy shows every Claude Code session in the Mac notch and lets you answer from there.',
      thumbnailUrl: `${SITE_URL}/demo.jpg`,
      contentUrl: `${SITE_URL}/demo.mp4`,
      uploadDate: '2026-11-14',
      duration: 'PT20S',
    },
  ],
};

export default function RootLayout({ children }: { children: React.ReactNode }) {
  return (
    <html lang="en" className={`${gabarito.variable} ${mono.variable}`}>
      <body>
        {children}
        <script type="application/ld+json" dangerouslySetInnerHTML={{ __html: JSON.stringify(jsonLd).replace(/</g, '\\u003c') }} />
      </body>
    </html>
  );
}
