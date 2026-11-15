import type { MetadataRoute } from 'next';
import { SITE_URL } from './site';

export default function sitemap(): MetadataRoute.Sitemap {
  return [{
    url: SITE_URL,
    lastModified: new Date(),
    changeFrequency: 'monthly',
    priority: 1,
    images: [`${SITE_URL}/site/needs-you.png`, `${SITE_URL}/site/sorted.png`, `${SITE_URL}/site/detail.png`],
    videos: [{
      title: 'AgentBuddy in 20 seconds',
      description: 'Every Claude Code session in your Mac notch.',
      thumbnail_loc: `${SITE_URL}/demo.jpg`,
      content_loc: `${SITE_URL}/demo.mp4`,
    }],
  }];
}
