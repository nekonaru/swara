import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'library_screen.dart';
import 'extra_screens.dart';
import 'albums_screen.dart';
import 'collections_screen.dart';
import 'dashboard_screen.dart';
import 'settings_screen.dart';
import 'search_screen.dart';
import 'package:swara/l10n/gen/app_localizations.dart';
import '../providers/library_provider.dart';
import '../widgets/mini_player.dart';

// ─────────────────────────────────────────────────────────────
// Library tab definitions (id, label, visible, order)
// The label below is the stored fallback; the displayed label is
// resolved via _tabLabel() so it follows the active locale.
// ─────────────────────────────────────────────────────────────

class _TabDef {
  final String id;
  final String label;
  bool visible;
  _TabDef({required this.id, required this.label, this.visible = true});
  _TabDef copy() => _TabDef(id: id, label: label, visible: visible);
}

const _kTabConfigKey = 'library_tab_config_v2';

final _defaultTabDefs = <_TabDef>[
  _TabDef(id: 'songs', label: 'Lagu'),
  _TabDef(id: 'albums', label: 'Album'),
  _TabDef(id: 'artists', label: 'Artis'),
  _TabDef(id: 'folders', label: 'Folder'),
  _TabDef(id: 'genres', label: 'Genre'),
];

// Build a widget from a tab id
Widget _tabWidget(String id) {
  switch (id) {
    case 'songs': return const LibraryScreen();
    case 'albums': return const AlbumsScreen();
    case 'artists': return const ArtistsScreen();
    case 'folders': return const FoldersScreen();
    case 'genres': return const GenresScreen();
    default: return const LibraryScreen();
  }
}

// ─────────────────────────────────────────────────────────────
// HomeScreen
// ─────────────────────────────────────────────────────────────

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  int _groupIndex = 0;
  DateTime? _lastBackPress;

  // Tab definitions for the Library
  late List<_TabDef> _allTabDefs;
  late TabController _libTabController;

  final _dashboardKey = GlobalKey<DashboardScreenState>();
  DateTime? _lastDashboardReload;
  // True after the dashboard tab was opened once, so the lazy first load
  // (ensureLoaded) runs exactly once and later visits use the reload guard.
  bool _dashboardFirstOpenDone = false;

  @override
  void initState() {
    super.initState();
    _allTabDefs = _defaultTabDefs.map((t) => t.copy()).toList();
    _libTabController = TabController(
        length: _allTabDefs.where((t) => t.visible).length, vsync: this);
    _loadTabConfig();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initLibrary());
  }

  Future<void> _loadTabConfig() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_kTabConfigKey);
    if (raw == null || raw.isEmpty) return;

    // Format: "id:visible" per item, order defines the tab order
    final parsed = raw
        .map((s) {
          final parts = s.split(':');
          if (parts.length != 2) return null;
          final def = _defaultTabDefs
              .firstWhere((d) => d.id == parts[0], orElse: () => _TabDef(id: '', label: ''));
          if (def.id.isEmpty) return null;
          return _TabDef(
              id: def.id, label: def.label, visible: parts[1] == '1');
        })
        .whereType<_TabDef>()
        .toList();

    // Add new tabs missing from the saved config
    for (final d in _defaultTabDefs) {
      if (!parsed.any((p) => p.id == d.id)) parsed.add(d.copy());
    }

    if (!mounted) return;
    _rebuildTabController(parsed);
  }

  Future<void> _saveTabConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _kTabConfigKey,
      _allTabDefs.map((t) => '${t.id}:${t.visible ? 1 : 0}').toList(),
    );
  }

  void _rebuildTabController(List<_TabDef> newDefs) {
    final enabledCount = newDefs.where((t) => t.visible).length;
    final oldCtrl = _libTabController;
    setState(() {
      _allTabDefs = newDefs;
      _libTabController = TabController(
          length: enabledCount < 1 ? 1 : enabledCount, vsync: this);
    });
    // Dispose after the frame so the animation does not crash
    WidgetsBinding.instance.addPostFrameCallback((_) => oldCtrl.dispose());
  }

  Future<void> _initLibrary() async {
    if (!mounted) return;
    late final LibraryProvider lib;
    try {
      lib = context.read<LibraryProvider>();
      // Fast startup path: DB load + device scan without internet fetch,
      // so the song list shows right after the first frame.
      await lib.autoLoadAndScanIfNeeded();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
            content: Text(AppLocalizations.of(context)!
                .homeLoadLibraryFailed('$e'))),
      );
    }
  }

  @override
  void dispose() {
    _libTabController.dispose();
    super.dispose();
  }

  // First dashboard visit runs the lazy first load (cached, not forced);
  // later visits reuse the time guarded forced reload below.
  void _openDashboardTab() {
    if (!_dashboardFirstOpenDone) {
      _dashboardFirstOpenDone = true;
      _dashboardKey.currentState?.ensureLoaded();
      return;
    }
    _maybeReloadDashboard();
  }

  // Reload the dashboard with a time guard: skip when data was just loaded
  // (< 2 seconds) so fast tab switches do not trigger repeated reloads.
  void _maybeReloadDashboard() {
    final now = DateTime.now();
    if (_lastDashboardReload != null &&
        now.difference(_lastDashboardReload!) < const Duration(seconds: 2)) {
      return;
    }
    _lastDashboardReload = now;
    _dashboardKey.currentState?.reload();
  }

  Future<bool> _onBackPressed() async {
    final now = DateTime.now();
    if (_lastBackPress == null ||
        now.difference(_lastBackPress!) > const Duration(seconds: 2)) {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            behavior: SnackBarBehavior.floating,
            content:
                Text(AppLocalizations.of(context)!.homePressAgainToExit),
            duration: const Duration(seconds: 3)),
      );
      return false;
    }
    SystemNavigator.pop();
    return false;
  }

  String _groupTitle(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    switch (_groupIndex) {
      case 0: return l.homeLibrary;
      case 1: return l.homeCollection;
      default: return l.homeDashboard;
    }
  }

  // Localized display label for a configurable library tab
  String _tabLabel(BuildContext context, _TabDef t) {
    final l = AppLocalizations.of(context)!;
    switch (t.id) {
      case 'songs': return l.homeTabSongs;
      case 'albums': return l.homeTabAlbums;
      case 'artists': return l.homeTabArtists;
      case 'folders': return l.homeTabFolders;
      case 'genres': return l.homeTabGenres;
      default: return t.label;
    }
  }

  // Library tab bar with a settings icon
  PreferredSizeWidget _buildLibraryTabBar() {
    final enabledTabs = _allTabDefs.where((t) => t.visible).toList();
    return PreferredSize(
      preferredSize: const Size.fromHeight(48),
      child: Row(
        children: [
          Expanded(
            child: TabBar(
              controller: _libTabController,
              isScrollable: enabledTabs.length > 3,
              tabAlignment: enabledTabs.length > 3
                  ? TabAlignment.start
                  : TabAlignment.fill,
              tabs: enabledTabs.map((t) => Tab(text: _tabLabel(context, t))).toList(),
            ),
          ),
          // Tab settings icon
          IconButton(
            constraints:
                const BoxConstraints(minWidth: 48, minHeight: 48),
            icon: const Icon(Icons.tune, size: 20),
            tooltip: AppLocalizations.of(context)!.homeTabSettings,
            onPressed: _showTabSettings,
          ),
        ],
      ),
    );
  }

  void _showTabSettings() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _TabSettingsSheet(
        initialDefs: _allTabDefs.map((t) => t.copy()).toList(),
        onApply: (newDefs) {
          _rebuildTabController(newDefs);
          _saveTabConfig();
        },
      ),
    );
  }

  void _openSearch() {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, anim, __) => const SearchScreen(),
        transitionsBuilder: (context, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  void _openSettings() {
    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, anim, __) => const SettingsScreen(),
        transitionsBuilder: (context, anim, __, child) =>
            FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabledTabs = _allTabDefs.where((t) => t.visible).toList();

    return PopScope(
      // canPop: false only vetoes pops for this Home (root) route.
      // Dialogs/bottom sheets/pushed pages are separate routes on top,
      // so pressing back while one is open still pops that route
      // with a single press without triggering the double-back logic below.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || !mounted) return;
        await _onBackPressed();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_groupTitle(context)),
          actions: [
            IconButton(
              icon: const Icon(Icons.search_outlined),
              tooltip: AppLocalizations.of(context)!.search,
              onPressed: _openSearch,
            ),
            IconButton(
              icon: const Icon(Icons.settings_outlined),
              tooltip: AppLocalizations.of(context)!.homeSettings,
              onPressed: _openSettings,
            ),
          ],
          bottom: _groupIndex == 0 ? _buildLibraryTabBar() : null,
        ),

        // IndexedStack: every page stays in memory
        body: IndexedStack(
          index: _groupIndex,
          children: [
            // Library - TabBarView
            TabBarView(
              controller: _libTabController,
              children: enabledTabs
                  .map((t) => _tabWidget(t.id))
                  .toList()
                  .let((list) => list.isEmpty
                      ? [const LibraryScreen()]
                      : list),
            ),

            // Collection - single screen (cards + playlists)
            const CollectionsScreen(),

            // Dashboard (lazy: no load until the tab is first opened)
            DashboardScreen(key: _dashboardKey, autoLoad: false),
          ],
        ),

        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MiniPlayer(),
            NavigationBar(
              selectedIndex: _groupIndex,
              onDestinationSelected: (i) {
                setState(() => _groupIndex = i);
                if (i == 2) _openDashboardTab();
              },
              destinations: [
                NavigationDestination(
                    icon: const Icon(Icons.library_music_outlined),
                    selectedIcon: const Icon(Icons.library_music),
                    label: AppLocalizations.of(context)!.homeLibrary),
                NavigationDestination(
                    icon: const Icon(Icons.folder_special_outlined),
                    selectedIcon: const Icon(Icons.folder_special),
                    label: AppLocalizations.of(context)!.homeCollection),
                NavigationDestination(
                    icon: const Icon(Icons.bar_chart_outlined),
                    selectedIcon: const Icon(Icons.bar_chart),
                    label: AppLocalizations.of(context)!.homeDashboard),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Tab Settings Sheet (drag reorder + toggle visibility)
// ─────────────────────────────────────────────────────────────

class _TabSettingsSheet extends StatefulWidget {
  final List<_TabDef> initialDefs;
  final void Function(List<_TabDef> newDefs) onApply;

  const _TabSettingsSheet({required this.initialDefs, required this.onApply});

  @override
  State<_TabSettingsSheet> createState() => _TabSettingsSheetState();
}

class _TabSettingsSheetState extends State<_TabSettingsSheet> {
  late List<_TabDef> _defs;

  @override
  void initState() {
    super.initState();
    _defs = widget.initialDefs.map((t) => t.copy()).toList();
  }

  void _reset() {
    setState(() {
      _defs = _defaultTabDefs.map((t) => t.copy()).toList();
    });
  }

  // Localized display label for a tab id
  String _labelOf(BuildContext context, _TabDef t) {
    final l = AppLocalizations.of(context)!;
    switch (t.id) {
      case 'songs': return l.homeTabSongs;
      case 'albums': return l.homeTabAlbums;
      case 'artists': return l.homeTabArtists;
      case 'folders': return l.homeTabFolders;
      case 'genres': return l.homeTabGenres;
      default: return t.label;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 12, 0),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l.homeTabSettings,
                          style: const TextStyle(
                              fontSize: 17, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(l.homeTabReorderHint,
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey[500])),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _reset,
                  child: Text(l.homeReset),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Reorderable list
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(context).size.height * 0.45,
            ),
            child: ReorderableListView(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              onReorderItem: (oldIdx, newIdx) {
                setState(() {
                  final item = _defs.removeAt(oldIdx);
                  _defs.insert(newIdx, item);
                });
              },
              children: [
                for (int i = 0; i < _defs.length; i++)
                  ListTile(
                    key: ValueKey(_defs[i].id),
                    leading: ReorderableDragStartListener(
                      index: i,
                      child: Icon(Icons.drag_handle,
                          color: Colors.grey[500], size: 22),
                    ),
                    title: Text(
                      _labelOf(context, _defs[i]),
                      style: TextStyle(
                        color: _defs[i].visible
                            ? cs.onSurface
                            : cs.onSurface.withValues(alpha: 0.4),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    trailing: GestureDetector(
                      onTap: () {
                        // At least 1 tab must stay enabled
                        final enabledCount =
                            _defs.where((t) => t.visible).length;
                        if (_defs[i].visible && enabledCount <= 1) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 3),
                                content: Text(l.homeMinOneTab)),
                          );
                          return;
                        }
                        setState(() => _defs[i].visible = !_defs[i].visible);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: _defs[i].visible ? cs.primary : Colors.transparent,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: _defs[i].visible
                                ? cs.primary
                                : cs.outline.withValues(alpha: 0.5),
                            width: 2,
                          ),
                        ),
                        child: _defs[i].visible
                            ? Icon(Icons.check,
                                size: 14, color: cs.onPrimary)
                            : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Divider(height: 1),

          // Buttons
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                    child: Text(l.cancel),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      widget.onApply(_defs);
                      Navigator.pop(context);
                    },
                    style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(24)),
                        padding: const EdgeInsets.symmetric(vertical: 12)),
                    child: Text(l.homeApply),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

extension _LetterExtension<T> on T {
  R let<R>(R Function(T) f) => f(this);
}
