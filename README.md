<picture>
  <source media="(prefers-color-scheme: dark)" srcset="brand/wordmark-dark.svg">
  <img src="brand/wordmark-ink.svg" alt="Hmmm" width="244" height="56">
</picture>

Offline period, HRT, and symptom tracker for Android, built with Flutter.

- A period is recorded by its start date, with an optional end date. A
  period with no end date is ongoing and runs to today while it is the latest
  record. An earlier period with no end date is shown as one day, marked "end
  not recorded", until an end date is set. Recording a start before a later
  period asks for its end date.
- HRT medication windows are derived from recorded facts: cyclical courses
  from a recorded period start (for example, progesterone from cycle day 15
  for 12 days), continuous courses from a recorded start date, fixed-interval
  courses from a recorded anchor date. Nothing is predicted. The calendar
  shows cycle days up to today and draws each course as a named band.
- Symptoms are logged per day with a 1-3 severity. Stopped medications keep
  their historical windows. Individual courses can be moved to a different
  start date, ended early, skipped, or restored.
- Data lives in a local SQLite database. Release builds request no network
  permission, and Android cloud backup is disabled. Phone-to-phone transfer
  during device setup carries the data across. Otherwise data leaves the
  device only through an export or print you start yourself: calendar (.ics),
  backup (.json, which can also be imported back), or PDF report.

## Install

1. Download an APK from the [latest release](https://github.com/benemon/Hmmm/releases/latest).
   The arm64 build suits most phones; the universal build runs on any.
2. Open the APK on the phone and allow installs from that source when Android
   asks.

Releases up to v0.3.2 were each signed with a different key, and Android only
installs an update signed with the same key as the installed app. Moving from
one of those releases to a later one needs a reinstall, and uninstalling
deletes the app's data:

1. In Hmmm, open Settings > Export & print > Export data and keep the .json
   file.
2. Uninstall Hmmm.
3. Install the new release.
4. Open Settings > Export & print > Import data and choose the .json file.

Later releases share one signing key and install over each other.

Brand assets live in [`brand/`](brand/) with usage rules in
[`brand/README.md`](brand/README.md).
