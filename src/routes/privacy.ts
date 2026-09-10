import { Hono } from 'hono';
import type { HonoEnv } from '../types';
import { privacyPage } from '../../website/privacy.mjs';

// Preserve the URL already used by the iOS app and App Store Connect.
// The standalone website builds from this same policy to prevent drift.
export const privacyRoutes = new Hono<HonoEnv>();
const policy = privacyPage({ appHost: true });
privacyRoutes.get('/privacy', (c) => c.html(policy));
