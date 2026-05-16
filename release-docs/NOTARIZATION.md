# HTTMELY Notarization

HTTMELY can be signed and packaged with:

```bash
cd viewer
./script/package_release.sh
```

That creates:

- `viewer/release/HTTMELY.app`
- `viewer/release/HTTMELY-1.0.0.dmg`

## Notarize

First store a notarytool keychain profile named `HTTMELY`:

```bash
xcrun notarytool store-credentials HTTMELY \
  --apple-id "APPLE_ID_EMAIL" \
  --team-id "TEAM_ID" \
  --password "<notarytool-password>"
```

Then run:

```bash
cd viewer
SIGN_IDENTITY="Developer ID Application: Your Name (TEAM_ID)" NOTARIZE=1 ./script/package_release.sh
```

The release script submits the DMG, waits for Apple, staples the accepted ticket, and runs a Gatekeeper check.

## Current Signing Defaults

- Bundle ID: `dev.realitytest.httmely`
- Minimum macOS: `14.0`
- Version: `1.0.0`
- Default notary profile: `HTTMELY`
- Signing identity: set with `SIGN_IDENTITY`

Override when needed:

```bash
VERSION=1.0.1 BUILD_NUMBER=2026051601 SIGN_IDENTITY="Developer ID Application: Your Name (TEAM_ID)" NOTARY_PROFILE=HTTMELY NOTARIZE=1 ./script/package_release.sh
```
