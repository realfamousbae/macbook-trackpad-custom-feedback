# Trackpad Feedback

[Читать по-русски](README.ru.md)

Trackpad Feedback is a macOS menu bar app that plays a sound when you press the built-in trackpad sharply. Ordinary clicks stay quiet. A sharp touch can trigger playback before the trackpad clicks.

## Installation

Use a MacBook with Apple Silicon, a built-in Force Touch trackpad, and macOS 15 or later. Tested on a MacBook Air M2 with macOS 15.

Download the ZIP, unzip it, and move `Trackpad Feedback.app` to Applications. The app is ad hoc signed and has no Apple notarization. The current app interface is in Russian. [Latest release](https://github.com/realfamousbae/macbook-trackpad-custom-feedback/releases/latest)

## Usage

On first launch, the app guides you through calibration with normal clicks, gradual presses, and short, sharp touches without a click. Open the ◉ menu to toggle playback on sharp presses, recalibrate, or test the sound.

The app installs the bundled `example.mp3` in its Sounds folder. Choose **Открыть папку звуков** (Open Sounds Folder) from the ◉ menu to replace the sample or add MP3, WAV, and M4A files. Files play in filename order and loop back to the first. Presses during playback are ignored.

Choose **Чувствительность** (Sensitivity) for the baseline setting or an adjustment of ±10 percentage points. The three trigger thresholds are 100%, 110%, and 120% of the calibrated threshold.

## Build from source

Run `./build.sh` from the repository root on a Mac with Xcode. The script creates `build/Trackpad Feedback.app` and bundles `Resources/example.mp3`.

After building, run the detection and playback regression checks.

```sh
xcrun swiftc -swift-version 6 Sources/Detection.swift Sources/Sounds.swift Tests/Regression.swift -o build/regression
build/regression Resources/example.mp3
```

The app reads touch data through the private `MultitouchSupport` framework. Compatibility may need to be rechecked after macOS updates. [Trackpad data layout](https://github.com/MatMercer/mactic/blob/main/docs/implementation.md)
