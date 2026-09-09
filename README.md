<picture>
  <source media="(prefers-color-scheme: dark)" srcset="brand/wordmark-dark.svg">
  <img src="brand/wordmark-ink.svg" alt="Hmmm" width="244" height="56">
</picture>

Offline period, HRT, and symptom tracker for Android, built with Flutter.

- Period start and end dates are recorded. HRT medication windows are derived
  from recorded facts: cyclical courses from a recorded period start (for
  example, progesterone from cycle day 15 for 12 days), continuous courses
  from a recorded start date, fixed-interval courses from a recorded anchor
  date. Nothing is predicted.
- Symptoms are logged per day with a 1-3 severity. Stopped medications keep
  their historical windows. Individual courses can be moved to a different
  start date, ended early, skipped, or restored.
- Data lives in a local SQLite database. Release builds request no network
  permission, and Android cloud backup is disabled. Data leaves the device
  only through an export or print you start yourself: calendar (.ics), backup
  (.json, which can also be imported back), or PDF report.

Brand assets live in [`brand/`](brand/) with usage rules in
[`brand/README.md`](brand/README.md).
