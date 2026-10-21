<div align="center">

<a href="https://dailyanimelist.web.app/">
  <img src="assets/images/dal-black-bg.png" alt="DailyAL" title="DailyAL" width="88"/>
</a>

# DailyAnimeList (DailyAL)

**An unofficial Flutter client for MyAnimeList (MAL), with fork-specific Ameo recommendations and improvements to search, list synchronization, notifications, and diagnostics.**

[![Discord](https://img.shields.io/discord/1147503264741478452.svg?label=Discord&logo=discord&logoColor=white)](https://discord.gg/ap4Wghv5e8)
[![Upstream Releases](https://img.shields.io/github/v/tag/JICA98/DailyAL?label=Upstream%20version&logo=github)](https://github.com/JICA98/DailyAL/releases)
[![License](https://img.shields.io/github/license/JICA98/DailyAL)](LICENSE)

</div>

> **About this repository:** This is a community fork of [JICA98/DailyAL](https://github.com/JICA98/DailyAL). It retains DailyAL's core MAL client functionality and adds fork-specific features and fixes. The upstream release and download links below refer to the original project, not a separate release published by this fork.

## Contents

- [Overview](#overview)
- [Features](#features)
- [Fork-specific improvements](#fork-specific-improvements)
- [Screenshots](#screenshots)
- [Download and build](#download-and-build)
- [Development setup](#development-setup)
- [Repository layout](#repository-layout)
- [Notes and limitations](#notes-and-limitations)
- [Credits and license](#credits-and-license)

## Overview

DailyAL is a Flutter-based client for exploring anime and manga from MyAnimeList. It brings catalog discovery, search, personal-list management, community content, and user customization into one application.

This fork also includes **Ameo**, an optional anime recommendation integration, along with reliability and usability improvements in notifications, search results, MAL list-status synchronization, and character/person detail loading.

## Features

### Anime and manga discovery

- Browse seasonal, airing, upcoming, popular, and ranked anime and manga.
- View title details, synopsis, statistics, genres, related titles, and recommendations.
- Read anime reviews and explore MyAnimeList community forums.
- Browse character and person information, including related images and voice-acting information where provided by the data service.

### Search and filtering

- Search across supported content categories, including anime, manga, characters, people, forums, clubs, featured content, and news.
- Use DailyAL's special search shortcuts, including `@` and `#` queries.
- Filter and sort results using the available category-specific controls.
- View available MyAnimeList list status, score, and progress information on supported anime and manga results.
- Receive clearer error feedback when external search services fail instead of having every failure appear as an ordinary empty result.

### Personal anime and manga lists

- View and update your personal MyAnimeList entries.
- Edit supported list fields, scores, and progress.
- Sort list entries using supported criteria such as title, score, start date, and update date.
- Keep cached list data and status updates synchronized across supported search and recommendation surfaces.

### Ameo anime recommendations

This fork integrates the external **Ameo/Sprout** recommendation service into DailyAL.

- Add the Ameo recommendation section through the customizable Home Page item settings.
- Open the dedicated recommendation screen and configure the supported recommendation options.
- Resolve the MyAnimeList profile from the signed-in account when possible, or configure a username where supported.
- Browse recommendations using DailyAL's familiar anime cards and open matching titles in the app.
- View prediction metadata and expandable recommendation explanations when the service returns them.
- Choose among the model identifiers supported by the integration: `2026-logq`, `2026-rc`, `2025-jax`, and `legacy`.
- Cache recommendation responses for a limited period and use usable cached results when a refresh fails.
- Refresh list-status information so recommendation cards can reflect relevant changes to your MAL list.

Ameo is an optional integration. Recommendations depend on the external service, a usable username/profile, network access, and the data returned by that service. Prediction values and explanations may be absent for some results.

### Anime release notifications

- Configure reminders for anime on your **Watching** list and notifications related to titles on **Plan to Watch**, according to the available notification preferences.
- Synchronize reminders against the user's MyAnimeList list and the schedule data available from the app's services.
- Refresh notification state during relevant preference changes and when the app resumes.
- Request notification and exact-alarm permissions independently where the platform requires them.
- Use the built-in test notification to check whether the app can schedule a notification.

Reminder scheduling is best-effort and depends on permissions, network responses, and schedule data. The app avoids treating an incomplete or failed list response as proof that the user's list is empty, helping prevent valid reminders from being removed accidentally.

### Themes and customization

- Choose from four seasonal dark themes: Spring, Summer, Fall, and Winter.
- Customize supported navigation and Home Page content.
- Adjust cache-related preferences and other available user settings.
- Configure the preferred title language and other presentation preferences where available.

## Fork-specific improvements

In addition to Ameo, this fork contains maintenance and reliability work across several parts of the application.

| Area | Improvements |
|---|---|
| MAL authentication and requests | Improved token-refresh handling and request behavior, including retry/error paths. |
| List-status synchronization | Preserve successful list edits as per-title snapshots and merge fresh status information into supported search and recommendation results. |
| Search | Improved pagination and result-field handling, producer filtering, retry behavior for Jikan requests, and error messages for failed searches. |
| Character and person details | Validate detail responses, retry unusable cached data, and provide an error state with selectable/copyable diagnostic information when loading fails. |
| Notifications | Use one-shot release reminders, reconcile against the user's relevant MAL lists, refresh when appropriate, and preserve existing reminders when list or schedule data is incomplete. |
| Android layouts | Improve safe-area and system-navigation insets for search filters and settings sheets to reduce controls being hidden behind system UI. |
| Profile and statistics | Improve list/profile data parsing and handling of chart data used by profile insights. |
| Logging | Add opt-in timestamped file logging and more structured diagnostics for investigating API and detail-loading failures. |
| Build workflow | Keep a manually triggered GitHub Actions workflow for producing an Android release APK artifact. |

These are code-level improvements; they do not imply that every external API or platform has been tested in every environment. See [Notes and limitations](#notes-and-limitations).

## Screenshots

The images below are the screenshots already included in the repository's English metadata.

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

## Download and build

### Download

For currently published upstream builds, check:

- [JICA98/DailyAL releases](https://github.com/JICA98/DailyAL/releases)
- [F-Droid package](https://f-droid.org/packages/io.github.jica98/)

Those distribution pages belong to the upstream project. This fork's repository currently includes a manually triggered GitHub Actions workflow for building an Android release APK; it does not, by itself, mean that a fork-specific release has been published.

### Build an Android APK with GitHub Actions

1. Open the repository's **Actions** tab.
2. Select **Build Android APK (Manual)**.
3. Choose **Run workflow** on the branch you want to build.
4. After the workflow completes, download the `DailyAL-Android-APK` artifact from that run.

The workflow installs Java 17, configures the stable Flutter channel, runs `flutter pub get`, and builds with `flutter build apk --release`.

### Build locally

The application is built with Flutter. See the setup instructions below to prepare a development environment.

## Development setup

### Requirements

- [Git](https://git-scm.com/downloads).
- [Flutter SDK](https://docs.flutter.dev/get-started/install) on the stable channel.
- A compatible Dart SDK. The root `pubspec.yaml` specifies Dart `>=3.2.6 <4.0.0`.
- An Android SDK and configured Android device/emulator for Android development.
- A configured desktop toolchain if you intend to target a desktop platform.

### Clone and install dependencies

```bash
git clone https://github.com/onemind66/DailyAL.git
cd DailyAL
flutter pub get
```

Run the app on a configured device or target:

```bash
flutter run
```

You can also open `dal-code.code-workspace` in Visual Studio Code and launch the `dailyanimelist` configuration with **F5**, if you use the repository's workspace tasks.

### Generated files and translations

When changing localization sources or generated models, use the repository's configured development tasks where possible. The corresponding commands include:

```bash
dart run intl_utils:generate
dart run build_runner build --delete-conflicting-outputs
python3 python/init.py
```

These commands are for regeneration/development workflows, not required for every normal app launch. Check the VS Code tasks and source scripts before running them; translation processing may have additional requirements.

### Optional diagnostics

The fork includes timestamped file logging intended to help investigate issues. Logging and diagnostic output can contain technical request context, so review it before sharing publicly and never include access tokens, credentials, or other secrets in issue reports.

## Repository layout

| Path | Purpose |
|---|---|
| `lib/` | Main Flutter application, screens, widgets, preferences, and services |
| `lib/features/ameo/` | Ameo recommendation integration and UI |
| `lib/api/` | MyAnimeList and DailyAL API clients, authentication, and data handling |
| `lib/notifservice.dart` | Anime release notification scheduling and reconciliation |
| `lib/util/file_logger.dart` | Optional timestamped diagnostic file logging |
| `dal-api/` | Dart API package and shared data models |
| `dal-rust-api/` | Rust API/service component included in the repository |
| `assets/` | Application images, fonts, and other bundled assets |
| `metadata/` | Store metadata and screenshots |
| `test/` | Flutter test sources, where present |
| `.github/workflows/` | GitHub Actions workflows, including the manual Android APK build |

## Notes and limitations

- **MyAnimeList and third-party services:** Search, list updates, schedule data, character/person details, and Ameo recommendations depend on external services and network availability.
- **Notifications:** Delivery depends on OS permissions, battery/background restrictions, alarm behavior, and the availability of valid schedule data. Use the in-app test notification when diagnosing setup issues.
- **Ameo:** It is a fork-specific integration, not a built-in MyAnimeList feature. Its results, models, prediction metadata, and explanations are controlled by the external service.
- **Build verification:** The existence of a build workflow documents the configured build path; it is not a guarantee that every commit has passed a full device test on every supported platform.
- **Platform support:** Flutter dependencies and platform folders alone do not guarantee a fully tested release for each platform. Validate the target platform's toolchain and native dependencies before distributing a build.
- **Privacy and diagnostics:** Do not publish OAuth tokens, credentials, or private account data. Inspect diagnostic logs before sharing them.
- **Upstream-only functionality:** This README documents capabilities visible in this fork's code and configuration. Do not assume that features available only in the upstream repository or its release builds are integrated here.

## Credits and license

DailyAL is based on the work of [JICA98 and contributors](https://github.com/JICA98/DailyAL). Please consult the repository's [LICENSE](LICENSE) and upstream project for license terms and attribution details.

Fork-specific additions are maintained in this repository. If you redistribute a build, make its origin clear and comply with the applicable license and third-party service terms.
