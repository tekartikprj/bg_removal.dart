# bg_removal_example_common

Shared by the two examples, `../bg_removal_example` (Android) and
`../bg_removal_example_web` (web), which never depend on each other: the
page that takes or picks a photo, removes its background, shows the cut-out
next to the original and saves it, plus the sample photo.

It depends on no engine: each app gives its own.

```dart
runApp(
  MaterialApp(
    home: BgRemovalExamplePage(
      remover: BgOnnxWebRemover(), // or BgMlKitRemover()...
      camera: false,
    ),
  ),
);
```

The sample photo is [Young woman with tote bag in Madison, Wisconsin
2020](https://commons.wikimedia.org/wiki/File:Young_woman_with_tote_bag_in_Madison,_Wisconsin_2020.jpg)
by John Benson, [CC BY 2.0](https://creativecommons.org/licenses/by/2.0),
resized.
