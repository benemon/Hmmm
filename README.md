<picture>
  <source media="(prefers-color-scheme: dark)" srcset="brand/wordmark-dark.svg">
  <img src="brand/wordmark-ink.svg" alt="Hmmm" width="244" height="56">
</picture>

Offline period, HRT, and symptom tracker for Android, built with Flutter.

- Period start and end dates are recorded; HRT medication windows are derived
  from recorded period starts (for example, progesterone from cycle day 15 for
  12 days). Nothing is predicted.
- Symptoms are logged per day with a 1-3 severity. Stopped medications keep
  their historical windows; individual courses can be marked ended early or
  skipped.
- Data lives in a local SQLite database. The app requests no network
  permission and opts out of device backups; the JSON export is the only way
  data leaves the device.

Brand assets live in [`brand/`](brand/) with usage rules in
[`brand/README.md`](brand/README.md).
