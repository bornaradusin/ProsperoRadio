# ProsperoRadio

Internet radio for PlayStation 5 homebrew.

**BlackBearReloaded**, the original developer, has stepped down. **bornaradusin** has taken over development and maintenance. Original authorship, copyright and licence notices are preserved.

## Features

Browse and search internet radio stations, save favourites, and control playback through a controller-operated interface.

## Installation

Download `PPSA99001.zip` from the [latest release](https://github.com/bornaradusin/ProsperoRadio/releases/latest). Extract it and install the complete `PPSA99001/` folder at `/data/homebrew/PPSA99001/` using your usual PS5 homebrew installation method.

**Title ID:** `PPSA99001` · **Version:** `01.000.010`

**Homebrew catalogue:** [Prospero Store](https://prosperostore.net/).

Use GitHub Releases for updates. Automatic-updater compatibility with the replacement service has not been verified.

## Building

See [Getting started](docs/GETTING_STARTED.md) for dependencies. From the project root:

```bash
make test
make app
```

Output: `dist/PPSA99001/`. Downloaded dependencies remain in `.deps/`. The GitHub build workflow is manual-only; releases are built and tested locally.

## Credits and licence

Original developer: **BlackBearReloaded**. Current developer and maintainer: **bornaradusin**.

**GPL-3.0-or-later.** See [LICENSE](LICENSE) and [third-party notices](THIRD_PARTY_NOTICES.md).
