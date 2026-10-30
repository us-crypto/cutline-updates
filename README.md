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
