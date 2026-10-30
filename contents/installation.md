---
title: Installation
description: "Install Carne from GitHub Releases or build from source."
keywords: ["carne", "install", "installation", "releases", "build"]
---

# Installation

## Prebuilt binaries (coming soon)

Prebuilt binaries for macOS and Linux will be published on the
[GitHub Releases](https://github.com/openpeeps/carne/releases) page. That page
does not exist yet; until the first release is cut, build from source below.

## Build from source

Requirements:

- Nim >= 2.2.0
- `nimble` (comes with Nim)
- On Linux: `libjavascriptcoregtk-4.1-dev`

```bash
git clone https://github.com/openpeeps/carne.git
cd carne
nimble install -Y
```

Or with `clue`:

```bash
clue install carne --build
```

Verify the install:

```text
carne --version
```

## Platform notes

- macOS: supported out of the box.
- Linux: requires `libjavascriptcoregtk-4.1-dev`.
- Windows: not supported yet.
