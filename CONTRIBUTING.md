# Contributing

Thanks for helping out. NotchDeck is small on purpose, so keep changes focused.

## Setup

```bash
make run    # build + launch
make test   # unit tests
```

Requires Xcode 15+ on macOS 14+. There is no Xcode project; open the folder in
Xcode (File > Open) and it will pick up `Package.swift`.

## Guidelines

- Keep it native (AppKit + SwiftUI). No web views, no third-party dependencies
  unless there is a very good reason.
- Anything that touches the pomodoro cycle or persistence should come with a
  test in `Tests/NotchDeckTests`.
- New settings must decode tolerantly (see `AppSettings.init(from:)`) so older
  `state.json` files keep loading.
- Run the app on both a notched MacBook and an external display if you touch
  `NotchGeometry` or `NotchWindowController`.

## Adding a widget

1. Add a case to `NotchTab` in `Models.swift` (title + SF Symbol).
2. Create `Views/<Name>Widget.swift`.
3. Add it to the `switch` in `ExpandedContent` (`Views/NotchRootView.swift`).
4. Persist state through `AppStore` if it needs to survive relaunches.

## Releasing

Push a tag like `v0.2.0`. CI builds the app, zips it and attaches it to a
GitHub release.
