# Diagnostics policy proposal

Approved by the owner 2026-09-10. Prepared in the repository; not an applied
production setting. The owner prefers a small first-release implementation.

## Evidence

Read-only Wrangler 4.92.0 service metadata download at 17:07:31 UTC confirmed:
observability enabled, 100% sampling, stored logs enabled, invocation logs
included, URL query redaction disabled, and tracing disabled. No tail consumers
or export destinations were returned. This command does not expose Logpush;
its absence is not proof that Logpush is disabled. No request logs were opened.
Temporary downloaded source and provider configuration were deleted afterward.

The Intervals callback in `src/routes/intervalsAuth.ts` receives `code` and
`state` in the URL. Cloudflare documents request URLs in invocation logs, so this
configuration permits retaining those parameters. This is a configuration-based
risk assessment, not a claim that a particular person's data was inspected.

The application-code fix removes raw unexpected errors from HTTP/MCP responses
and console logs. It does not remove Cloudflare's attached request metadata.

## Recommended first-release policy

Do not retain or export Worker console, invocation, or trace logs. Keep native
aggregate health/performance metrics. This reduces stored request details;
diagnosing an individual failed request becomes harder. Stored aggregate D1
usage log rows also become unavailable. No application or training records are
deleted or changed by this proposal.

Exact proposed Wrangler fields, leaving the remaining configuration intact:

```json
{
  "observability": {
    "enabled": false,
    "logs": {
      "enabled": false,
      "persist": false,
      "invocation_logs": false,
      "destinations": []
    },
    "traces": {
      "enabled": false,
      "persist": false,
      "destinations": []
    }
  },
  "logpush": false,
  "tail_consumers": []
}
```

This would stop future Worker log persistence/export after an authorized
production deployment. It does not erase historical logs or control independent
Cloudflare account/security analytics. Cloudflare documents a maximum seven-day
Workers Logs retention period; previously exported copies, if any, require
separate verification. No historical-log deletion is proposed here.

## Alternative

Keep retained diagnostics and disclose the actual collected fields. Before
release, establish query redaction and an exact provider field/retention/export
policy, including path identifiers and any request metadata on custom logs.
The installed Wrangler schema does not support `redact_query_string`; adding
an ignored configuration key is not a fix. Turning off invocation logs alone
does not establish that custom-log metadata contains no identifiers.

## Authority and verification

The owner approved the aggregate-metrics-only recommendation. This authorizes
preparing and reviewing repository changes; applying them
to production remains part of the separately approved candidate release.
After deployment, re-read provider settings and verify with synthetic requests
before finalizing App Privacy declarations. Native aggregate metrics and any
independent account-level analytics still need accurate disclosure assessment.

Sources checked 2026-09-10:
[Workers Logs](https://developers.cloudflare.com/workers/observability/logs/workers-logs/),
[Observability](https://developers.cloudflare.com/workers/observability/),
[script settings](https://developers.cloudflare.com/api/resources/workers/subresources/scripts/subresources/settings/methods/get/),
and the installed Wrangler configuration schema and download implementation.
