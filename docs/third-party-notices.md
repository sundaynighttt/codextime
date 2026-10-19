# Third-party notices

## CodexBar provider logos

The same PNG marks are also bundled in `ios/Shared/ProviderAssets.xcassets` for the iPhone app and widget, and in `windows/CodexTime.Windows/Assets` for the Windows 0.4.0 candidate. The logo MIT notice is included in the iPhone bundles as `ThirdPartyNotices.txt` and in the Windows distribution's [THIRD_PARTY_NOTICES.txt](../windows/THIRD_PARTY_NOTICES.txt).

The monochrome provider marks below are derived from [CodexBar](https://github.com/steipete/CodexBar), pinned to commit [`6480977b47f6e4ffd5dcaae1cb0c7fdf34ee449e`](https://github.com/steipete/CodexBar/tree/6480977b47f6e4ffd5dcaae1cb0c7fdf34ee449e).

| Bundled asset | Original SVG |
| --- | --- |
| `macos/Sources/CodexUsageMonitor/Resources/codex.png` | [ProviderIcon-codex.svg](https://github.com/steipete/CodexBar/blob/6480977b47f6e4ffd5dcaae1cb0c7fdf34ee449e/Sources/CodexBar/Resources/ProviderIcon-codex.svg) |
| `macos/Sources/CodexUsageMonitor/Resources/grok.png` | [ProviderIcon-grok.svg](https://github.com/steipete/CodexBar/blob/6480977b47f6e4ffd5dcaae1cb0c7fdf34ee449e/Sources/CodexBar/Resources/ProviderIcon-grok.svg) |
| `macos/Sources/CodexUsageMonitor/Resources/claude.png` | [ProviderIcon-claude.svg](https://github.com/steipete/CodexBar/blob/6480977b47f6e4ffd5dcaae1cb0c7fdf34ee449e/Sources/CodexBar/Resources/ProviderIcon-claude.svg) |

The SVG path geometry is unchanged. macOS AppKit rendered each source as a black mark on a transparent 128 × 128 RGBA canvas, with proportional scaling to a maximum 112-pixel visible dimension and centered padding. The PNGs are intended for `NSImage.isTemplate = true` so macOS controls their menu-bar appearance.

These marks identify the corresponding third-party services. Brand names and trademarks remain with their respective owners. This app is not affiliated with those providers.

### MIT License

[Upstream license](https://github.com/steipete/CodexBar/blob/6480977b47f6e4ffd5dcaae1cb0c7fdf34ee449e/LICENSE):

```text
MIT License

Copyright (c) 2026 Peter Steinberger

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```


## Windows SQLite dependencies

The Windows 0.4.0 candidate pins these packages in [CodexTime.Windows.csproj](../windows/CodexTime.Windows/CodexTime.Windows.csproj) for the bounded Cursor database reader:

| Package | Version | License reference |
| --- | --- | --- |
| Microsoft.Data.Sqlite | 10.0.13 | [NuGet package and MIT license](https://www.nuget.org/packages/Microsoft.Data.Sqlite/10.0.13) |
| SQLitePCLRaw.bundle_e_sqlite3 | 3.0.5 | [NuGet package and Apache-2.0 license](https://www.nuget.org/packages/SQLitePCLRaw.bundle_e_sqlite3/3.0.5) |
| SQLite native package | 3.53.4 | [NuGet package and its License Info](https://www.nuget.org/packages/SQLite/3.53.4) |

The Windows [THIRD_PARTY_NOTICES.txt](../windows/THIRD_PARTY_NOTICES.txt) includes the provider-logo MIT text, the exact SQLitePCLRaw package copyright notices and complete Apache-2.0 license, SQLite's packaged public-domain notice, Microsoft.Data.Sqlite's MIT notice, and the bundled .NET runtime license and third-party notices. Package version, runtime pin, notice files, and the reader's native-version check must be reviewed together when updating SQLite. This dependency does not permit access to any additional Cursor key, profile, or credential source.
