<p align="center">
  <img src="assets/readme/app-icon-rounded.png" alt="Anvil app icon" width="128" height="128">
</p>

<h1 align="center">Anvil</h1>

Anvil is a free, open-source macOS menu bar app for making small, personal Mac apps with AI. Describe what you want, and Anvil generates, builds, and saves a native SwiftUI app you can launch, edit, and export to your Applications folder.

Anvil is a fork of [Ironsmith](https://github.com/Jeidoban/Ironsmith) by Jade Westover, rebuilt as a fully self-hosted tool: no accounts, no credits, no backend, no store. You bring your own models - local via Ollama, or hosted via your own API keys for OpenAI, Anthropic, Gemini, or any OpenAI-compatible API. Signing in with your existing ChatGPT account is also supported.

<br>

<p align="center">
  <img src="assets/readme/all-apps.png" alt="Several generated Mac apps with the Anvil menu bar popover open in front.">
</p>

## What It Does

- **Builds real Mac apps.** Generated apps are native Swift and SwiftUI apps that you can create, run, edit, and export from the menu bar.
- **Works with local AI.** Anvil was designed with local AI support in mind, and has Ollama support out of the box. You can also connect any OpenAI compatible API, so LM Studio and Llama.cpp work great too.
- **Supports hosted models too.** Bring your own API keys for OpenAI, Anthropic, and Gemini. Using your existing ChatGPT login is also supported.
- **Offers specialized coding agents.** Choose Anvil's in-house agents for tiny macOS apps or OpenAI's Codex for more complex projects.
- **Doesn't require Xcode.** Every generated app is a Swift package and is built entirely with the lightweight Xcode command line tools rather than full Xcode. In fact Anvil itself doesn't even use Xcode!
- **Sandboxes every app by default.** Generated apps are built as signed app bundles with sandboxing and hardened runtime enabled, greatly reducing the impact of bugs, mistakes, or malicious behavior. Sensitive permissions such as camera and microphone access must also be explicitly enabled. However, you can disable these protections, and if you do, it's highly recommended that you review the code before running it.

## Examples

Anvil works best for focused utilities: the small apps you wish existed but wouldn't want to hunt down or build yourself. That said, with more capable models like GPT-5.6 Sol or Fable 5, you can create some surprisingly sophisticated apps.

| Synthesizer | Painting App | HEIF Converter |
| --- | --- | --- |
| <img src="assets/readme/synthesizer.png" alt="Synthesizer generated with Anvil." width="280"> | <img src="assets/readme/drawing-tools.png" alt="Painting app generated with Anvil." width="280"> | <img src="assets/readme/heif-converter.png" alt="HEIF converter generated with Anvil." width="280"> |

| SVG Editor | Notepad | Network Visualizer |
| --- | --- | --- |
| <img src="assets/readme/svg-editor.png" alt="SVG editor generated with Anvil." width="280"> | <img src="assets/readme/notepad.png" alt="Notepad generated with Anvil." width="280"> | <img src="assets/readme/network-visualizer.png" alt="Network visualizer generated with Anvil." width="280"> |

Some examples of prompts you can try:

- "Make a utility that renames a folder of screenshots by date and window title."
- "Build a tiny app that splits a PDF into one file per page."
- "Build a clipboard cleaner that strips tracking parameters from copied URLs."
- "Make a small CSV inspector that highlights duplicate rows and missing values."

## Install

Download the latest Anvil build from [GitHub Releases](https://github.com/corismix/Anvil/releases/latest).

Anvil requires macOS 26 or newer and supports both Intel and Apple Silicon Macs. Make sure Apple Intelligence is enabled where available; Anvil uses it to create app icons and provide the built-in Foundation Model.

On first launch, Anvil checks for the Xcode Command Line Tools as generated apps are compiled locally. If they are missing, macOS will prompt you to install them. You can also install them manually:

```sh
xcode-select --install
```

## Develop

Development requires macOS 26 or newer and the Xcode Command Line Tools. Xcode itself is not required.

Build the development app:

```sh
script/build.sh
```

Build and run the development app:

```sh
script/build.sh run
```

Run tests:

```sh
script/test.sh
```

Clean SwiftPM and script outputs:

```sh
script/clean.sh
```
Copy `Config/.env.example` to `Config/.env` and fill in `ANVIL_DEV_SIGN_IDENTITY` with your Apple Development ID to avoid repeated keychain asks when running new builds.

Every push and pull request is built and tested on GitHub Actions (macOS 26 runner).

## Contribute

Issues and pull requests are welcome. Start with [CONTRIBUTING.md](CONTRIBUTING.md) for the local workflow and PR expectations.

## License

Anvil is licensed under the [GNU General Public License v3.0](LICENSE), like the upstream project.

Anvil is a fork of [Ironsmith](https://github.com/Jeidoban/Ironsmith), originally created by Jade Westover and contributors. Upstream copyright and attribution are preserved in LICENSE, the bundled GPLv3 text, and the app's About window.
