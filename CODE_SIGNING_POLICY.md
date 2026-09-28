# Code signing policy

WoWQuestVoice does not currently have a code-signing certificate, so public beta executables are unsigned. Windows may show an unknown-publisher or SmartScreen warning. Release artifacts are built by GitHub Actions, and SHA-256 checksums are published with releases so users can verify downloaded files.

The project may apply for community code signing again after it has established broader public adoption. This document will be updated before any signed artifact is published.

## Team roles

- Committers and reviewers: [repository contributors](https://github.com/roengray/WoWQuestVoice/graphs/contributors) with write access
- Approvers: [repository owner](https://github.com/roengray)

Changes from outside contributors are merged only after review by a maintainer. Build and installer changes receive special review because they determine the contents of release artifacts. If code signing becomes available, every signing request will require manual approval by the repository owner.

## Privacy

See the [privacy policy](PRIVACY.md). Network transfer of quest text is disabled by default and requires an explicit installation choice.
