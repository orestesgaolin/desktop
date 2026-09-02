// Flutter's desktop windowing API is experimental on the main channel.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/src/widgets/_window.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../palette.dart';

const _browserInk = Color(0xFF252A28);
const _browserMuted = Color(0xFF777D78);
const _browserChrome = Color(0xFFF0EEE9);
const _browserRail = Color(0xFFE3E0D8);
const _browserAccent = Color(0xFFB55F49);

const windowingApiSnippet = '''final controller = WindowController(
  size: const Size(800, 600),
  title: 'Inspector',
);

Window(
  controller: controller,
  child: const Inspector(),
);''';

const _windowingApiHtml = '''<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <style>
    :root { color-scheme: light; font-family: -apple-system, BlinkMacSystemFont, sans-serif; }
    body { margin: 0; background: #f5f3ee; color: #252a28; }
    main { max-width: 920px; margin: 0 auto; padding: 64px 52px; }
    p.label { color: #b55f49; font-size: 13px; font-weight: 700; letter-spacing: .16em; text-transform: uppercase; }
    h1 { font-size: 48px; line-height: 1.08; font-weight: 500; margin: 18px 0 20px; }
    pre { margin-top: 34px; padding: 30px 34px; overflow: auto; border-radius: 18px; background: #252a28; color: #d8dee9; font: 18px/1.6 ui-monospace, SFMono-Regular, Menlo, monospace; }
    .kw { color: #c792ea; }
    .type { color: #82aaff; }
    .str { color: #c3e88d; }
    .num { color: #f78c6c; }
    footer { margin-top: 24px; color: #777d78; font-size: 14px; }
  </style>
</head>
<body>
  <main>
    <p class="label">Flutter desktop windowing</p>
    <h1>Creating a native window</h1>
    <pre><code><span class="kw">final</span> controller = <span class="type">WindowController</span>(
  size: <span class="kw">const</span> <span class="type">Size</span>(<span class="num">800</span>, <span class="num">600</span>),
  title: <span class="str">'Inspector'</span>,
);

<span class="type">Window</span>(
  controller: controller,
  child: <span class="kw">const</span> <span class="type">Inspector</span>(),
);</code></pre>
    <footer>flutter.dev/blog/desktop-windowing-apis</footer>
  </main>
</body>
</html>''';

class BrowserTab extends ChangeNotifier {
  BrowserTab(this.id, this.fallbackTitle, this.initialUri, {this.initialHtml});

  final int id;
  final String fallbackTitle;
  final Uri initialUri;
  final String? initialHtml;

  WebViewController? _controller;
  String? title;
  Uri? uri;
  double progress = 0;
  bool loading = true;
  String? error;

  String get displayTitle =>
      title?.trim().isNotEmpty == true ? title!.trim() : fallbackTitle;

  String get displayAddress {
    final current = uri;
    if (initialHtml != null &&
        (current == null ||
            current.scheme == 'about' ||
            current.scheme == 'data')) {
      return initialUri.toString();
    }
    return (current ?? initialUri).toString();
  }

  WebViewController get controller {
    if (_controller != null) return _controller!;
    final next = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            uri = Uri.tryParse(url);
            loading = true;
            error = null;
            notifyListeners();
          },
          onProgress: (value) {
            progress = value / 100;
            notifyListeners();
          },
          onPageFinished: (url) async {
            uri = Uri.tryParse(url);
            loading = false;
            progress = 1;
            title = await _controller?.getTitle();
            notifyListeners();
          },
          onWebResourceError: (webError) {
            if (webError.isForMainFrame ?? true) {
              loading = false;
              error = webError.description;
              notifyListeners();
            }
          },
        ),
      );
    _controller = next;
    if (initialHtml case final html?) {
      unawaited(next.loadHtmlString(html, baseUrl: 'https://flutter.dev/'));
    } else {
      unawaited(next.loadRequest(initialUri));
    }
    return next;
  }

  Future<void> navigate(String value) async {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    final parsed = Uri.tryParse(trimmed);
    final target = parsed != null && parsed.hasScheme
        ? parsed
        : Uri.https(
            trimmed.contains('.') ? trimmed : 'www.google.com',
            trimmed.contains('.') ? '' : '/search',
            trimmed.contains('.') ? null : {'q': trimmed},
          );
    await controller.loadRequest(target);
  }
}

class DetachedBrowserTab {
  const DetachedBrowserTab({required this.tab, required this.window});

  final BrowserTab tab;
  final WindowController window;
}

class _DetachedWindowDelegate with WindowControllerDelegate {
  _DetachedWindowDelegate(this.workspace, this.tabId);

  final BrowserWorkspace workspace;
  final int tabId;

  @override
  void onWindowDestroyed() {
    workspace._windowDestroyed(tabId);
    super.onWindowDestroyed();
  }
}

class BrowserWorkspace extends ChangeNotifier {
  BrowserWorkspace._();

  static final BrowserWorkspace instance = BrowserWorkspace._();

  final List<BrowserTab> tabs = <BrowserTab>[
    BrowserTab(
      1,
      'Windowing API',
      Uri.parse('https://flutter.dev/windowing-api'),
      initialHtml: _windowingApiHtml,
    ),
    BrowserTab(
      2,
      'Flutter & Friends',
      Uri.parse('https://flutterfriends.dev/'),
    ),
    BrowserTab(3, 'Flutter', Uri.parse('https://flutter.dev')),
  ];
  final List<DetachedBrowserTab> _detached = <DetachedBrowserTab>[];
  int _nextId = 4;
  int selectedId = 1;

  List<DetachedBrowserTab> get detachedTabs =>
      List<DetachedBrowserTab>.unmodifiable(_detached);

  bool isDetached(BrowserTab tab) => _detached.any((entry) => entry.tab == tab);

  BrowserTab? get selectedTab {
    for (final tab in tabs) {
      if (tab.id == selectedId && !isDetached(tab)) return tab;
    }
    for (final tab in tabs) {
      if (!isDetached(tab)) return tab;
    }
    return null;
  }

  void select(BrowserTab tab) {
    if (isDetached(tab)) {
      _detached.firstWhere((entry) => entry.tab == tab).window.activate();
      return;
    }
    selectedId = tab.id;
    notifyListeners();
  }

  void addTab() {
    final tab = BrowserTab(
      _nextId++,
      'New tab',
      Uri.parse('https://flutter.dev/showcase'),
    );
    tabs.add(tab);
    selectedId = tab.id;
    notifyListeners();
  }

  void detach(BrowserTab tab) {
    if (isDetached(tab)) return;
    final window = WindowController(
      size: const Size(1040, 720),
      constraints: const BoxConstraints(minWidth: 700, minHeight: 480),
      title: tab.displayTitle,
      delegate: _DetachedWindowDelegate(this, tab.id),
    );
    _detached.add(DetachedBrowserTab(tab: tab, window: window));
    final next = selectedTab;
    if (next != null) selectedId = next.id;
    notifyListeners();
  }

  void reattach(BrowserTab tab) {
    final entry = _detached.where((item) => item.tab == tab).firstOrNull;
    entry?.window.destroy();
  }

  void _windowDestroyed(int tabId) {
    final index = _detached.indexWhere((entry) => entry.tab.id == tabId);
    if (index == -1) return;
    final entry = _detached.removeAt(index);
    entry.window.dispose();
    selectedId = tabId;
    notifyListeners();
  }
}

class BrowserWorkspaceView extends StatelessWidget {
  const BrowserWorkspaceView({super.key});

  @override
  Widget build(BuildContext context) {
    final workspace = BrowserWorkspace.instance;
    return ListenableBuilder(
      listenable: workspace,
      builder: (context, _) {
        final selected = workspace.selectedTab;
        return ColoredBox(
          color: _browserChrome,
          child: Row(
            children: [
              _TabRail(workspace: workspace),
              Expanded(
                child: selected == null
                    ? _AllTabsDetached(onActivate: workspace.select)
                    : BrowserSurface(
                        key: ValueKey('attached-${selected.id}'),
                        tab: selected,
                        onDetach: () => workspace.detach(selected),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class DetachedBrowserWindow extends StatelessWidget {
  const DetachedBrowserWindow({super.key, required this.tab});

  final BrowserTab tab;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: spruce),
      home: Scaffold(
        backgroundColor: _browserChrome,
        body: SafeArea(
          child: BrowserSurface(
            key: ValueKey('detached-${tab.id}'),
            tab: tab,
            detached: true,
            onDetach: () => BrowserWorkspace.instance.reattach(tab),
          ),
        ),
      ),
    );
  }
}

class BrowserSurface extends StatefulWidget {
  const BrowserSurface({
    super.key,
    required this.tab,
    required this.onDetach,
    this.detached = false,
  });

  final BrowserTab tab;
  final VoidCallback onDetach;
  final bool detached;

  @override
  State<BrowserSurface> createState() => _BrowserSurfaceState();
}

class _BrowserSurfaceState extends State<BrowserSurface> {
  late final TextEditingController _address;
  late final FocusNode _addressFocus;

  @override
  void initState() {
    super.initState();
    _address = TextEditingController(text: widget.tab.displayAddress);
    _addressFocus = FocusNode();
    widget.tab.addListener(_tabChanged);
  }

  @override
  void didUpdateWidget(BrowserSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tab != widget.tab) {
      oldWidget.tab.removeListener(_tabChanged);
      widget.tab.addListener(_tabChanged);
      _address.text = widget.tab.displayAddress;
    }
  }

  void _tabChanged() {
    if (!mounted) return;
    if (!_addressFocus.hasFocus) {
      _address.text = widget.tab.displayAddress;
    }
    setState(() {});
  }

  @override
  void dispose() {
    widget.tab.removeListener(_tabChanged);
    _address.dispose();
    _addressFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.tab.controller;
    return Padding(
      padding: const EdgeInsets.all(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFF8F7F3),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withValues(alpha: .8)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x17000000),
              blurRadius: 22,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Column(
            children: [
              _BrowserToolbar(
                tab: widget.tab,
                controller: controller,
                address: _address,
                addressFocus: _addressFocus,
                detached: widget.detached,
                onDetach: widget.onDetach,
              ),
              if (widget.tab.loading)
                LinearProgressIndicator(
                  value: widget.tab.progress == 0 ? null : widget.tab.progress,
                  minHeight: 2,
                  color: _browserAccent,
                  backgroundColor: Colors.transparent,
                )
              else
                const SizedBox(height: 2),
              Expanded(child: WebViewWidget(controller: controller)),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrowserToolbar extends StatelessWidget {
  const _BrowserToolbar({
    required this.tab,
    required this.controller,
    required this.address,
    required this.addressFocus,
    required this.detached,
    required this.onDetach,
  });

  final BrowserTab tab;
  final WebViewController controller;
  final TextEditingController address;
  final FocusNode addressFocus;
  final bool detached;
  final VoidCallback onDetach;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          const SizedBox(width: 8),
          _ToolbarButton(
            tooltip: 'Back',
            icon: Icons.arrow_back_rounded,
            onPressed: () async {
              if (await controller.canGoBack()) unawaited(controller.goBack());
            },
          ),
          _ToolbarButton(
            tooltip: 'Forward',
            icon: Icons.arrow_forward_rounded,
            onPressed: () async {
              if (await controller.canGoForward()) {
                unawaited(controller.goForward());
              }
            },
          ),
          _ToolbarButton(
            tooltip: 'Refresh',
            icon: Icons.refresh_rounded,
            onPressed: controller.reload,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 36,
              decoration: BoxDecoration(
                color: const Color(0xFFE8E6E0),
                borderRadius: BorderRadius.circular(10),
              ),
              alignment: Alignment.center,
              child: TextField(
                controller: address,
                focusNode: addressFocus,
                onSubmitted: tab.navigate,
                textInputAction: TextInputAction.go,
                style: const TextStyle(fontSize: 12, color: _browserInk),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.lock_outline_rounded, size: 14),
                  border: InputBorder.none,
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 10),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          _ToolbarButton(
            tooltip: detached ? 'Return tab to main window' : 'Detach tab',
            icon: detached
                ? Icons.call_merge_rounded
                : Icons.open_in_new_rounded,
            emphasized: true,
            onPressed: onDetach,
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }
}

class _ToolbarButton extends StatelessWidget {
  const _ToolbarButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    this.emphasized = false,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: emphasized ? _browserAccent : Colors.transparent,
        foregroundColor: emphasized ? Colors.white : _browserMuted,
      ),
      icon: Icon(icon, size: 18),
      onPressed: onPressed,
    );
  }
}

class _TabRail extends StatelessWidget {
  const _TabRail({required this.workspace});

  final BrowserWorkspace workspace;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 172,
      color: _browserRail,
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(10, 2, 8, 14),
            child: Row(
              children: [
                _WindowDot(color: Color(0xFFD27762)),
                _WindowDot(color: Color(0xFFD9AD5F)),
                _WindowDot(color: Color(0xFF6E9D82)),
                Spacer(),
                Icon(
                  Icons.auto_awesome_rounded,
                  size: 16,
                  color: _browserMuted,
                ),
              ],
            ),
          ),
          for (final tab in workspace.tabs)
            _TabTile(
              tab: tab,
              selected: workspace.selectedTab == tab,
              detached: workspace.isDetached(tab),
              onTap: () => workspace.select(tab),
            ),
          const Spacer(),
          TextButton.icon(
            onPressed: workspace.addTab,
            icon: const Icon(Icons.add_rounded, size: 17),
            label: const Text('New space'),
            style: TextButton.styleFrom(
              foregroundColor: _browserMuted,
              alignment: Alignment.centerLeft,
              textStyle: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowDot extends StatelessWidget {
  const _WindowDot({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 8,
    height: 8,
    margin: const EdgeInsets.only(right: 5),
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class _TabTile extends StatelessWidget {
  const _TabTile({
    required this.tab,
    required this.selected,
    required this.detached,
    required this.onTap,
  });

  final BrowserTab tab;
  final bool selected;
  final bool detached;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tab,
      builder: (context, _) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Material(
          color: selected ? const Color(0xFFF8F7F3) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    detached
                        ? Icons.picture_in_picture_alt_rounded
                        : Icons.public_rounded,
                    size: 15,
                    color: detached ? _browserAccent : _browserMuted,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tab.displayTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                        color: _browserInk,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AllTabsDetached extends StatelessWidget {
  const _AllTabsDetached({required this.onActivate});
  final ValueChanged<BrowserTab> onActivate;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.space_dashboard_outlined,
            size: 34,
            color: _browserMuted,
          ),
          const SizedBox(height: 12),
          const Text('Every tab is in its own window'),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => onActivate(BrowserWorkspace.instance.tabs.first),
            child: const Text('Bring a window forward'),
          ),
        ],
      ),
    );
  }
}
