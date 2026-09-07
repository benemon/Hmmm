# Hmmm

Offline period, HRT, and symptom tracker for Android, built with Flutter.

- Period start and end dates are recorded; HRT medication windows are derived
  from recorded period starts (for example, progesterone from cycle day 15 for
  12 days). Nothing is predicted.
- Symptoms are logged per day with a 1-3 severity. Stopped medications keep
  their historical windows.
- Data lives in a local SQLite database. The app requests no network
  permission and opts out of device backups; the JSON export is the only way
  data leaves the device.
