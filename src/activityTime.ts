/** Only explicitly zoned provider timestamps carry an absolute instant. */
export function activityInstant(value: unknown): number | null {
  const zonedTimestamp = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?(?:Z|[+-]\d{2}:\d{2})$/;
  if (typeof value !== 'string' || !zonedTimestamp.test(value)) return null;
  const civil = new Date(`${value.slice(0, 19)}Z`);
  if (!Number.isFinite(civil.getTime()) || civil.toISOString().slice(0, 19) !== value.slice(0, 19)) return null;
  const ms = Date.parse(value);
  return Number.isSafeInteger(ms) ? ms : null;
}

/** Validate optional source timing without treating the civil proxy as UTC. */
export function validActivitySourceTime(
  utc: unknown,
  zone: unknown,
  date: string,
  localMs: number | null,
): boolean {
  if (utc == null) return zone == null;
  if (typeof utc !== 'number' || !Number.isSafeInteger(utc) || !Number.isFinite(new Date(utc).getTime())) return false;
  if (localMs == null || Math.abs(localMs - utc) > 14 * 3_600_000) return false;
  if (zone == null) return true; // Source zone unavailable; first observed civil day is retained.
  if (typeof zone !== 'string' || zone.length > 100) return false;
  // Foundation also accepts fixed-offset identifiers that Intl does not.
  // Preserve their explicit offset without assigning an inferred IANA zone.
  const fixedOffset = /^(?:GMT|UTC)([+-])(\d{2})(\d{2})$/.exec(zone);
  if (fixedOffset) {
    const hours = Number(fixedOffset[2]);
    const minutes = Number(fixedOffset[3]);
    if (hours > 14 || minutes >= 60) return false;
    const direction = fixedOffset[1] === '+' ? 1 : -1;
    const expected = utc + direction * (hours * 60 + minutes) * 60_000;
    return expected === localMs && new Date(expected).toISOString().slice(0, 10) === date;
  }
  try {
    const parts = new Intl.DateTimeFormat('en-CA', {
      timeZone: zone,
      year: 'numeric',
      month: '2-digit',
      day: '2-digit',
      hour: '2-digit',
      minute: '2-digit',
      second: '2-digit',
      hourCycle: 'h23',
    }).formatToParts(utc);
    const fields = Object.fromEntries(parts.map(p => [p.type, p.value]));
    const civil = `${fields.year}-${fields.month}-${fields.day}`;
    const expected = Date.parse(`${civil}T${fields.hour}:${fields.minute}:${fields.second}Z`) + ((utc % 1000) + 1000) % 1000;
    return civil === date && expected === localMs;
  } catch {
    return false;
  }
}
