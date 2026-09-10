// A deliberately small, reviewable English filter for shared text. Private
// originals and catalog exercise names are untouched. Reports cover context
// and evasions this list cannot detect.
const objectionable = /(?<![\p{L}\p{N}])(?:fuck(?:ing|er|ers)?|motherfuck(?:er|ers|ing)?|shit|bullshit|assholes?|bitch(?:es)?|cunts?|niggers?|niggas?|faggots?|retard(?:ed|s)?|porn(?:ography)?|kill\s+yourself)(?![\p{L}\p{N}])/iu;

export function sharedText(value: string | null, fallback = 'Content hidden'): string | null {
  if (value === null) return null;
  const normalized = value.normalize('NFKC').replace(/[\u200B-\u200D\uFEFF]/g, '');
  return objectionable.test(normalized) ? fallback : value;
}

export const groupReportReasons = ['harassment', 'hate', 'sexual_content', 'threats', 'other'] as const;
export type GroupReportReason = typeof groupReportReasons[number];

export function isGroupReportReason(value: unknown): value is GroupReportReason {
  return typeof value === 'string' && groupReportReasons.some((reason) => reason === value);
}
