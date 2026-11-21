<p align="center">
  <img src="ios/Runner/Assets.xcassets/AppIcon.appiconset/icon-1024.png" width="120" alt="Spicci">
</p>

<h1 align="center">Spicci</h1>

<p align="center">A personal finance app for iPhone. Your data stays on the phone.</p>

## Features

- Accounts with their real balance, matching the bank
- Fast expense entry with a keypad, category suggestions and tags
- Piggy banks inside an account, filled automatically or by hand
- Planned big expenses and subscriptions, with reminders
- Monthly budgets per category
- Analysis by period, category and net worth over time
- Optional AI comments that only receive totals, never single transactions or notes
- Automatic JSON backups to a folder you choose, so data survives deleting the app
- Face ID lock
- English and Italian

## Build

Requires Flutter 3.38 or later.

```sh
flutter pub get
flutter test
tool/build_ipa.sh   # unsigned build in dist/Spicci.ipa
```

Install `dist/Spicci.ipa` with SideStore, or run the app from Xcode with your own team.
