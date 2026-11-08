# TG Desktop Landscape IPA

Build of Telegram iOS 13.1.2 with the `tg-desktop-landscape` mod.

The workflow checks out the official Telegram iOS source at tag `release-13.1.2`,
applies the files from `changes/`, and builds an unsigned/fake-signed IPA with the
official fake codesigning material. The resulting IPA must be signed with
Sideloadly/AltStore or installed with TrollStore.
