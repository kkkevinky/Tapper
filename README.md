# Tapper

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="Tapper-logo-dark.png">
  <img alt="Tapper" src="Tapper-logo-light.png" width="358">
</picture>

Tapper gives the Apple Magic Mouse two things macOS leaves out: tap to click, and switching Spaces with two fingers while the screen follows them. Your palm can stay on the mouse for both.

Version 1.0. Runs on macOS 13 or later; developed and tested on macOS 27 with the USB-C Magic Mouse.

English | [中文](README_zh.md) | [日本語](README_ja.md)

## Features

### Tap to click

- **Tap** anywhere on the front two thirds of the mouse to left-click. Taps on the back third are ignored, so a resting palm never clicks.
- **Tap twice** quickly to double-click.
- **Tap with two fingers** to right-click, as on a trackpad. Both fingers land and lift together; the time and movement limits of a one-finger tap apply.
- **Drag**: tap, touch again and keep the finger down, then move the mouse. Lift the finger to drop.
- **Light taps count.** A brief, light touch that the mouse barely registers still clicks.
- **Resting fingers don't get in the way.** A finger left still on the mouse for half a second is ignored, so another finger can tap next to it.
- **Pressing still works.** Pressing the mouse as usual clicks once; Tapper never adds a second click. Pressing the right side of the mouse still right-clicks (**System Settings → Mouse → Secondary click**). Tapping the right side to right-click is off by default ([Advanced settings](#advanced-settings)).

### Switch Spaces with two fingers

Swipe left or right with two fingers. After a short distance, the neighboring Space slides in and follows your fingers; lift them to finish. Fingers moving left bring in the Space on the right, as on a trackpad.

- **Palm down is fine.** Your palm or the side of your hand can rest on the mouse while two fingers swipe.
- **No stray scrolling.** Once Tapper recognizes the swipe, the window under the pointer stops scrolling sideways.
- **One Space per swipe.** Once the Space has started moving, lifting always completes the switch. Lift before that point to call it off. At the first or last Space, no switch happens, and the window under the pointer may scroll sideways instead.

Before you use it, turn off the system's own Magic Mouse gesture in **System Settings → Mouse → More Gestures → Swipe between full-screen applications**. Tapper leaves two-finger swipes alone while that setting is on, so a swipe never switches twice.

### Also in the menu

- **Pointer Speed**: a slider for the system-wide mouse speed, from 0 to 8.
- **Sensitivity Settings…**: tune how taps are told apart from scrolling.
- **Two-Finger Zoom** (experimental, off by default): slide two fingers toward the front of the mouse to zoom in, toward the back to zoom out, in apps that support pinch zoom.
- **Launch at Login** and **Prevent Sleep (Keep Running)**.

## Requirements

- macOS 13 or later. Space switching has been tested on macOS 27.
- An Apple Magic Mouse.
- Xcode or the Command Line Tools (`xcode-select --install`) to build. Running the unit tests needs Xcode.

## Install

Tapper is built from source:

```bash
git clone https://github.com/kkkevinky/Tapper.git
cd Tapper
bash install-final.sh
```

The script builds a universal app (Apple Silicon and Intel), quits any copy that is running, installs it as `/Applications/Tapper.app`, and then asks (y/N) whether to open it. The previous version is kept as a zip in `build/backups/`, not as a second app: macOS would otherwise open whichever copy has the higher build number. To try a build without installing it, run `bash test-and-install.sh --test-only`.

To install by hand instead, quit Tapper first, then:

```bash
bash build.sh
rm -rf /Applications/Tapper.app
ditto build/Tapper.app /Applications/Tapper.app
```

Every build is signed ad hoc, so macOS asks for Accessibility access again after you install a new build.

## First launch

1. Open Tapper from Applications. A mouse icon appears in the menu bar; Tapper has no Dock icon.
2. macOS asks for Accessibility access. Turn on **Tapper** in **System Settings → Privacy & Security → Accessibility**. Tapper starts within a second of access being granted. If you take longer than a minute, it shows its own prompt; choose **Retry** there.
3. Turn on **Launch at Login** in the menu if you want Tapper to start with your Mac.
4. For Space switching, turn off **Swipe between full-screen applications** as described above.

Tapper needs Accessibility access to post clicks and zoom gestures. It reads touches through Apple's private MultitouchSupport framework, which is why it can't be in the Mac App Store and may need an update after a major macOS release.

## The menu

| Item | What it does |
| --- | --- |
| Status | `Running (1 Magic Mouse)`, `Waiting for Magic Mouse` or `Disabled`. |
| Tap to Click | Turns tap clicks, two-finger right-clicks included, on or off. It is on again at every launch. With Two-Finger Zoom off, turning it off also pauses Space switching. |
| Two-Finger Zoom | Turns zoom on or off. Saved across launches. |
| Launch at Login | Starts Tapper when you log in. |
| Prevent Sleep (Keep Running) | Keeps the Mac from going to sleep while Tapper runs and the Mac is on power (the display can still sleep). Off by default. |
| Pointer Speed | Sets the speed for every mouse on the Mac. **Restore Default** returns to the speed you had when Tapper first ran. |
| Sensitivity Settings… | Opens the settings window below. |
| Accessibility Instructions… | Shows how to grant access. |
| About Tapper / Quit Tapper | |

## Sensitivity settings

Changes apply as soon as you move a slider and are kept across launches.

| Slider | Default | Meaning |
| --- | --- | --- |
| Max Tap Duration | 0.35 s | A touch longer than this is not a tap. |
| Movement Tolerance | 8 px | How far the pointer may move during a tap. |
| Double-Tap Window | 0.30 s | Time allowed between the two taps of a double-click or drag. |
| Surface Movement Limit | 4 % | How far the finger may slide on the mouse before the touch counts as scrolling. |
| Surface Path Limit | 10 % | The same, for the total distance the finger travels. |
| Scroll Velocity Limit | 1.0 /s | A finger moving faster than this is scrolling. |
| Min Tap Duration | 0.03 s | Shorter touches are ignored. Raising it makes taps stricter. |
| Right-Click Hold Time | 0.16 s | Hold time for a right-click tap. Only used when tap right-click is on. |
| Left/Right Boundary | 60 % | Where the right-click side starts. Only used when tap right-click is on. |

The same window holds the zoom options: **Enable Two-Finger Zoom**, **Reverse zoom direction** and **Zoom sensitivity** (0.5× to 2.0×). **Reset to Defaults** restores every value and also turns Two-Finger Zoom off.

## Advanced settings

A few options have no menu yet. Set them in Terminal, then quit and reopen Tapper:

```bash
# Right-click with a slightly longer tap on the right side of the mouse (off by default)
defaults write io.github.kkkevinky.tapper io.github.kkkevinky.tapper.tune.rightTapEnabled -bool true

# Stop tapping with two fingers from right-clicking (on by default)
defaults write io.github.kkkevinky.tapper io.github.kkkevinky.tapper.tune.twoFingerTapEnabled -bool false

# How a two-finger swipe switches Spaces: dockswipe (default), instant, hotkey or off
defaults write io.github.kkkevinky.tapper io.github.kkkevinky.tapper.tune.swipeMode -string instant

# Reverse the swipe direction
defaults write io.github.kkkevinky.tapper io.github.kkkevinky.tapper.tune.swipeInvert -bool true
```

- `dockswipe`: the Space follows your fingers.
- `instant`: the Space switches as soon as your fingers have moved a short way.
- `hotkey`: Tapper presses your **Move left a Space** / **Move right a Space** shortcut from **System Settings → Keyboard → Keyboard Shortcuts → Mission Control**.

To go back to a default, delete the key, for example `defaults delete io.github.kkkevinky.tapper io.github.kkkevinky.tapper.tune.swipeMode`.

## Troubleshooting

**Taps do nothing.** Check that Tapper is on in **Privacy & Security → Accessibility**. After installing a new build, turn the switch off and on, or remove Tapper and add `/Applications/Tapper.app` again. If the status reads `Waiting for Magic Mouse`, check that Tapper has Accessibility access and that the mouse is connected. Taps on the back third of the mouse are ignored by design.

**Every tap clicks twice.** Another tap-to-click app is still running. Quit it and remove it from **System Settings → General → Login Items**.

**Tapping twice with two fingers opens Mission Control.** That is the system's own Magic Mouse gesture. Turn off **Mission Control** in **System Settings → Mouse → More Gestures** to keep only the right-clicks.

**Two-finger swipes don't switch Spaces.** Turn off **Swipe between full-screen applications** (see above), and make sure **Tap to Click** is on. At the first or last Space, a swipe can't switch any further.

## Uninstall

1. Turn off **Launch at Login** in Tapper's menu. If you changed the pointer speed, press **Restore Default** first.
2. Quit Tapper and delete `/Applications/Tapper.app`, and any `Tapper_backup_*.app` that older install scripts left next to it.
3. Optionally remove Tapper from **Privacy & Security → Accessibility** and delete its settings with `defaults delete io.github.kkkevinky.tapper`.

## Privacy

Tapper has no network code and sends nothing anywhere. It stores its settings in its own preferences and writes gesture details to the local macOS log (subsystem `io.github.kkkevinky.tapper`).

## Credits and license

Tapper is based on [Mouse Toucher](https://github.com/slopcore/mousetoucher) by Roger Hughes and is released under the MIT License; see [LICENSE](LICENSE).

Two-finger Space switching adapts code from InstantSpaceSwitcher, FasterSwiper and palmpad. Their licenses are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Thanks to everyone who reverse-engineered and documented the MultitouchSupport framework.
