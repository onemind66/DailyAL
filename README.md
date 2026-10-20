<div align="center">

<a href="https://dailyanimelist.web.app/">
    <img src="assets/images/dal-black-bg.png" alt="DailyAL" title="DailyAL" width="80"/>
</a>

# DailyAnimeList — MyAnimeList Client

An unofficial Flutter client for MyAnimeList (MAL), with anime and manga discovery, personal list management, forums, and additional recommendation features.

[![Discord Users](https://img.shields.io/discord/1147503264741478452.svg?label=&labelColor=6A7EC2&color=7389D8&logo=discord&logoColor=FFFFFF)](https://discord.gg/ap4Wghv5e8)
[![GitHub Downloads](https://img.shields.io/github/downloads/JICA98/DailyAL/total?label=downloads&labelColor=27303D&color=0D1117&logo=github&logoColor=FFFFFF)](https://github.com/JICA98/DailyAL/releases)
[![GitHub Stars](https://img.shields.io/github/stars/JICA98/DailyAL?label=stars&labelColor=27303D&color=0D1117&logo=github&logoColor=FFFFFF)](https://github.com/JICA98/DailyAL)
[![License: MIT](https://img.shields.io/github/license/JICA98/DailyAL?labelColor=27303D&color=818cf8)](LICENSE)

[![GitHub Releases](https://img.shields.io/github/v/tag/JICA98/DailyAL?label=Releases&logo=github&logoColor=FFFFFF)](https://github.com/JICA98/DailyAL/releases)
[![F-Droid](https://img.shields.io/f-droid/v/io.github.jica98?logo=f-droid&logoColor=FFFFFF)](https://f-droid.org/packages/io.github.jica98/)

</div>

> **Download:** The app is no longer listed on Google Play. Check [GitHub Releases](https://github.com/JICA98/DailyAL/releases) or [F-Droid](https://f-droid.org/packages/io.github.jica98/) for available distributions.

## Features

### Anime and Manga Discovery

- Browse seasonal, upcoming, popular, and ranked anime.
- View anime and manga synopses, statistics, related titles, and recommendations.
- Read anime reviews and explore catalog content.
- Browse MyAnimeList forums and discussions.

### Personal Lists

- View and edit personal anime and manga lists.
- Update supported list information and scores.
- Sort list entries by title, score, start date, and update date.
- Use cached list data to support the app's list and recommendation flows.

### Search

- Search using the `@` and `#` shortcuts.
- Benefit from cached search results.

### Themes and Customization

- Choose from four dark seasonal themes: Spring, Summer, Fall, and Winter.
- Customize the bottom navigation bar.
- Adjust the cache update frequency.

### Ameo Recommendations

This fork includes an Ameo recommendation section alongside the existing DailyAL functionality.

- Load recommendations using a MyAnimeList username.
- Open the recommendation page to access its settings.
- Display recommendations in a horizontally browsable section.
- Refresh recommendations when relevant MyAnimeList list-status changes are reported by the app.

Recommendation availability depends on the configured username and the external recommendation service.

## Screenshots

<div style="overflow-x: auto; white-space: nowrap;">
    <img src="metadata/en-US/images/phoneScreenshots/Screenshot_1.png" alt="DailyAL screenshot 1" width="200"/>
    <img src="metadata/en-US/images/phoneScreenshots/Screenshot_2.png" alt="DailyAL screenshot 2" width="200"/>
    <img src="metadata/en-US/images/phoneScreenshots/Screenshot_3.png" alt="DailyAL screenshot 3" width="200"/>
    <img src="metadata/en-US/images/phoneScreenshots/Screenshot_4.png" alt="DailyAL screenshot 4" width="200"/>
    <img src="metadata/en-US/images/phoneScreenshots/Screenshot_5.png" alt="DailyAL screenshot 5" width="200"/>
    <img src="metadata/en-US/images/phoneScreenshots/Screenshot_6.png" alt="DailyAL screenshot 6" width="200"/>
    <img src="metadata/en-US/images/phoneScreenshots/Screenshot_7.png" alt="DailyAL screenshot 7" width="200"/>
    <img src="metadata/en-US/images/phoneScreenshots/Screenshot_8.png" alt="DailyAL screenshot 8" width="200"/>
</div>

## Getting Started

### Requirements

- [Flutter SDK](https://docs.flutter.dev/get-started/install).
- A compatible Dart SDK. The root `pubspec.yaml` specifies `>=3.2.6 <4.0.0`.
- Git.
- A configured Flutter device, emulator, or supported desktop target.

### Clone and Run

Clone this fork:

```bash
git clone https://github.com/onemind66/DailyAL.git
cd DailyAL
```

Fetch the Flutter dependencies:

```bash
flutter pub get
```

Run the application on a configured target:

```bash
flutter run
```

Alternatively, open `dal-code.code-workspace` in Visual Studio Code and launch the `dailyanimelist` configuration with **F5**.

### Generated Files and Translations

The repository defines development tasks for localization generation, generated Dart code, and translation processing.

Run the corresponding command only when you need to regenerate those files:

```bash
dart run intl_utils:generate
dart run build_runner build --delete-conflicting-outputs
python3 python/init.py
```

These commands correspond to the repository's `intl generate`, `build runner`, and `python translate` VS Code tasks.

## Project Structure

| Path | Purpose |
|---|---|
| `lib/` | Main Flutter application, UI, features, and API clients |
| `lib/features/ameo/` | Ameo recommendation feature |
| `assets/` | Images, fonts, and application assets |
| `dal-api/` | Dart API package and shared models |
| `dal-rust-api/` | Rust service |
| `metadata/` | Application metadata and screenshots |
| `test/` | Flutter tests |

## API and Data Handling

The application includes MyAnimeList API integration and local caching used by its catalog, personal-list, and recommendation flows.

The repository also contains separate Dart and Rust API components. Running those components independently may require additional runtime dependencies and service configuration. Consult their source code and configuration files before starting them separately.

## Development and Security

- Keep generated files consistent with their source definitions.
- Do not commit access tokens, credentials, or other secrets.
- Keep changes to fork-specific functionality separate from upstream-only features until those features have actually been integrated.

## Upstream Project

DailyAL is based on [JICA98/DailyAL](https://github.com/JICA98/DailyAL). This repository contains fork-specific development in addition to the upstream project.

## License

Distributed under the MIT License. See [LICENSE](LICENSE) for details.
