import { describe, expect, it } from 'vitest';
import { privacyRoutes } from '../src/routes/privacy';
import { privacyPage } from '../website/privacy.mjs';

describe('public privacy policy', () => {
  it('serves the shared policy without an account, database, or provider credentials', async () => {
    const response = await privacyRoutes.request('/privacy');
    expect(response.status).toBe(200);
    expect(response.headers.get('content-type')).toContain('text/html');
    expect(await response.text()).toBe(privacyPage({ appHost: true }));
  });
});
