import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'data/library_repository.dart';
import 'reading/library_screen.dart';
import 'reading/settings_screen.dart';
import 'sync/api_client.dart';
import 'sync/sync_engine.dart';
import 'theme/app_tokens.dart';
import 'theme/appearance.dart';

/// A tab, and the icons and label that stand for it.
class _Destination {
  final IconData icon;
  final IconData selectedIcon;
  final String label;

  const _Destination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });
}

/// The frame every screen outside a book sits in.
///
/// Each tab keeps its own `Scaffold` and its own app bar. The alternative,
/// one bar owned here, turns every tab's actions into data this class has to
/// carry, including the library's rule about disabling them while a book
/// opens. The bar belongs to the screen that knows what its actions do.
///
/// The reader is not a tab. `BookOpener` pushes it above this route, full
/// screen, with no navigation bar under it: the whole reading surface is a
/// tap target and the anchor Y is configurable per profile, so a bar along
/// the bottom is a mis-tap magnet. Pushing it also keeps its `canPop: false`
/// and its single Escape-and-back handler working unchanged.
class AppShell extends StatefulWidget {
  final LibraryRepository repository;
  final SyncEngine sync;
  final ApiClient api;
  final AppearanceController appearance;

  /// Which tab shows first. Present for tests, which would otherwise have to
  /// tap their way to the tab they are about to assert on.
  final int initialTab;

  static const int libraryTab = 0;
  static const int settingsTab = 1;

  const AppShell({
    super.key,
    required this.repository,
    required this.sync,
    required this.api,
    required this.appearance,
    this.initialTab = libraryTab,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  /// Two tabs, not the three the UI brief describes.
  ///
  /// Home has no content until progress, covers and the continue card land.
  /// A tab that renders an explanation of what will eventually be there is
  /// the placeholder the brief rules out for Home's own stats strip, and it
  /// would be the first screen anyone opening the live URL sees. The
  /// destination is a list entry, so Home arrives by adding one.
  static const _destinations = <_Destination>[
    _Destination(
      icon: Icons.menu_book_outlined,
      selectedIcon: Icons.menu_book,
      label: 'Library',
    ),
    _Destination(
      icon: Icons.tune_outlined,
      selectedIcon: Icons.tune,
      label: 'Settings',
    ),
  ];

  /// `Ctrl+1` and `Ctrl+2`, indexed alongside the destinations so a new tab
  /// gets its shortcut without a second list to keep in step.
  static const _digits = <LogicalKeyboardKey>[
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
  ];

  late int _index = widget.initialTab;

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  @override
  Widget build(BuildContext context) {
    final body = _FadingIndexedStack(
      index: _index,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : AppMotion.state,
      children: [
        LibraryScreen(
          repository: widget.repository,
          sync: widget.sync,
          api: widget.api,
          issueStamp: widget.sync.issueStamp,
        ),
        SettingsScreen(
          repository: widget.repository,
          issueStamp: widget.sync.issueStamp,
          appearance: widget.appearance,
        ),
      ],
    );

    final wide = MediaQuery.sizeOf(context).width >= AppNav.railBreakpoint;

    return CallbackShortcuts(
      bindings: {
        for (var i = 0; i < _destinations.length; i++)
          SingleActivator(_digits[i], control: true): () => _select(i),
      },
      // The shortcuts resolve from whatever holds focus upward, and on a
      // fresh route nothing does. This node makes sure something in the
      // chain is inside `CallbackShortcuts` from the first frame.
      //
      // It covers this route only. `Ctrl+1` while a book is open does
      // nothing, which is right: the reader is pushed above the shell and
      // its own keys belong to it.
      child: Focus(
        autofocus: true,
        child: wide ? _withRail(context, body) : _withBar(context, body),
      ),
    );
  }

  Widget _withBar(BuildContext context, Widget body) {
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        // Labels always, never on selection alone. An icon that names its
        // destination only once you are there is colour-as-signal in another
        // form, and section 9 rules that out.
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: _barHeight(context),
        destinations: [
          for (final destination in _destinations)
            NavigationDestination(
              icon: Icon(destination.icon),
              selectedIcon: Icon(destination.selectedIcon),
              label: destination.label,
            ),
        ],
      ),
    );
  }

  Widget _withRail(BuildContext context, Widget body) {
    final hairline =
        Theme.of(context).dividerTheme.thickness ?? AppHairline.width;

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _index,
            onDestinationSelected: _select,
            labelType: NavigationRailLabelType.all,
            destinations: [
              for (final destination in _destinations)
                NavigationRailDestination(
                  icon: Icon(destination.icon),
                  selectedIcon: Icon(destination.selectedIcon),
                  label: Text(destination.label),
                ),
            ],
          ),
          // Reads its own thickness from the divider theme, so the 2dp
          // hairline high contrast asks for arrives here without this
          // deciding anything about contrast.
          VerticalDivider(width: hairline, thickness: hairline),
          Expanded(child: body),
        ],
      ),
    );
  }

  /// The bar's height, grown by whatever the reader's text size adds to a
  /// label.
  ///
  /// [AppNav.barHeight] is shorter than Material's 80dp default, which is
  /// only safe while the label is the size the theme says. Nothing here
  /// clamps the scaler, so the height follows it instead: the extra a
  /// scaled label needs is added to the base rather than taken out of the
  /// icon's room.
  double _barHeight(BuildContext context) {
    final label = Theme.of(context).textTheme.labelMedium;
    final size = label?.fontSize ?? 12;
    final lineHeight = label?.height ?? 1.2;
    final grown = MediaQuery.textScalerOf(context).scale(size) - size;

    return AppNav.barHeight + grown * lineHeight;
  }
}

/// Shows one of [children], cross-fading when [index] changes.
///
/// `IndexedStack` keeps every tab in the tree, which is what this needs:
/// the library's scroll offset and its drift subscription have to survive a
/// look at settings, and a rebuilt subtree loses both. What it cannot do is
/// fade, and section 10 of the UI brief rules out sliding a full screen
/// sideways on a build whose raster runs on the main thread. Opacity over
/// 120ms is the cheap axis.
///
/// A tab at zero opacity goes offstage rather than transparent, so it is not
/// laid out, painted, hit-tested or read out while it is hidden. It stays in
/// the tree throughout.
class _FadingIndexedStack extends StatefulWidget {
  final int index;
  final Duration duration;
  final List<Widget> children;

  const _FadingIndexedStack({
    required this.index,
    required this.duration,
    required this.children,
  });

  @override
  State<_FadingIndexedStack> createState() => _FadingIndexedStackState();
}

class _FadingIndexedStackState extends State<_FadingIndexedStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: widget.duration,
    // Starts finished. The first tab is already the one showing.
    value: 1,
  );

  late int _showing = widget.index;
  int? _leaving;

  @override
  void didUpdateWidget(_FadingIndexedStack old) {
    super.didUpdateWidget(old);

    // Picks up a duration of zero the moment the platform reports that
    // animations are off, rather than on the next tab change after that.
    _fade.duration = widget.duration;

    if (widget.index != old.index) {
      _leaving = _showing;
      _showing = widget.index;
      _fade.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fade,
      builder: (context, _) {
        return Stack(
          fit: StackFit.expand,
          children: [
            for (var i = 0; i < widget.children.length; i++)
              _layer(i, widget.children[i]),
          ],
        );
      },
    );
  }

  Widget _layer(int i, Widget child) {
    final double opacity;
    if (i == _showing) {
      opacity = _fade.value;
    } else if (i == _leaving) {
      opacity = 1 - _fade.value;
    } else {
      opacity = 0;
    }

    final visible = opacity > 0;

    return Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        // Taps land on the tab that is arriving, never on the one on its way
        // out, for the 120ms both are on screen.
        child: IgnorePointer(
          ignoring: i != _showing,
          child: Opacity(opacity: opacity, child: child),
        ),
      ),
    );
  }
}
