import { describe, expect, it } from 'vitest';
import fixtures from '../ios/TresFortTests/Fixtures/ActivityTime.json';
import { activityInstant, validActivitySourceTime } from '../src/activityTime';

describe('source timing contract shared with iOS', () => {
  it.each(fixtures)('$name', f => {
    expect(validActivitySourceTime(Date.parse(f.utc), f.zone, f.local.slice(0, 10), Date.parse(f.local))).toBe(true);
  });
  it('does not invent an instant from a civil timestamp or a missing source', () => {
    expect(activityInstant('2026-06-18T23:30:00')).toBeNull();
    expect(activityInstant(null)).toBeNull();
    expect(activityInstant('2026-02-30T23:30:00Z')).toBeNull();
    expect(activityInstant('2026-06-18T23:30:00-07:00')).toBe(Date.parse('2026-06-19T06:30:00Z'));
  });
  it('rejects inconsistent or invalid source metadata', () => {
    const f = fixtures[0]!;
    const utc = Date.parse(f.utc), local = Date.parse(f.local), date = f.local.slice(0, 10);
    expect(validActivitySourceTime(utc, 'Asia/Tokyo', date, local)).toBe(false);
    expect(validActivitySourceTime(utc, 'invalid/timezone', date, local)).toBe(false);
    expect(validActivitySourceTime(utc, 'GMT-0060', date, local)).toBe(false);
    expect(validActivitySourceTime(utc, 'GMT-1700', date, local)).toBe(false);
    expect(validActivitySourceTime(utc + 0.1, f.zone, date, local)).toBe(false);
    expect(validActivitySourceTime(null, f.zone, date, local)).toBe(false);
    expect(validActivitySourceTime(utc, null, date, local)).toBe(true);
    expect(validActivitySourceTime(undefined, undefined, date, local)).toBe(true);
  });
});
