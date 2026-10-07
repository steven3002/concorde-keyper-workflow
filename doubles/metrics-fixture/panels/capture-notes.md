# Metrics Fixtures Capture Notes

Recorded responses for permitted Grafana public dashboard panels.

- Source Host: `https://grafana.metrics.shutter.network`
- Dashboard UID: `2b52906b091a445989638922fbe69e5e`
- Endpoint Pattern: `POST https://grafana.metrics.shutter.network/api/public/dashboards/2b52906b091a445989638922fbe69e5e/panels/<panel_id>/query`
- Capture Date: 2026-10-07
- Headers: `Content-Type: application/json`
- Query Body: `{"timeRange":{"from":"now-7d","to":"now","timezone":"utc"},"intervalMs":60000,"maxDataPoints":2}`

## Recorded Panels

| Panel ID | Metric / Duty | Size (bytes) | Status | File |
|---|---|---|---|---|
| 1 | 7-day uptime (api set) | 16,029 | 200 OK | `panel-1.json` |
| 2 | 7-day uptime (gnosis set) | 4,653 | 200 OK | `panel-2.json` |
| 5 | Online status now | 22,390 | 200 OK | `panel-5.json` |
| 6 | Sync status | 22,822 | 200 OK | `panel-6.json` |
| 7 | Running version | 25,822 | 200 OK | `panel-7.json` |
| 9 | Last seen timestamp | 17,191 | 200 OK | `panel-9.json` |

## Fixture Behavior Notes

- In fixture runs, `metrics-fixture` serves these recorded responses for the respective panel query paths.
- The fixture server returns deterministic recorded data and ignores the relative `timeRange` in the request body.
- Live values change over time; fixtures remain static for reproducible test verification.
