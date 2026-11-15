# Cutline updates

This is the public update feed for [Cutline](https://github.com/us-crypto/cutline).

Cutline checks `version.json` on this repo when it opens, then again every 30 minutes. If `version` here is newer than the copy that is running, Cutline shows an update banner on its own.

Copyright © 2026 Cutline. All rights reserved.

## Ship an update

1. Publish the new Cutline build.
2. Edit `version.json` in this repo. Raise `version` (for example `1.0.1`) and write what changed in `notes`.

```json
{
  "version": "1.0.1",
  "notes": "What changed.",
  "released": "2026-10-30"
}
```

Keep this repository public. Cutline reads it from the browser and has no GitHub login.

## Android app

The Android app has its own feed, `android.json`, and its own releases here (tags that start with `android-`). `version.json` above belongs to the older web version and is left as it is.

To ship a new Android version:

1. In the app repository, raise `version.code` by 1 and `version.name` by one small step in `config/app.properties`.
2. Here, open **Actions**, choose **Release Cutline**, press **Run workflow**, and type what changed.

The workflow builds and signs the app, attaches the APK and the Google Play bundle to a new release, and updates `android.json`. Installed copies then update themselves inside the app, and older versions stop until they do.

The privacy policy for the store listing is in [`PRIVACY.md`](PRIVACY.md).
