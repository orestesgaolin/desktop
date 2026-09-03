import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// A muted, looping video intended for presentation slides.
class AssetVideo extends StatefulWidget {
  const AssetVideo({
    super.key,
    required this.asset,
    this.fit = BoxFit.contain,
    this.autoplay = true,
    this.looping = true,
  });

  final String asset;
  final BoxFit fit;
  final bool autoplay;
  final bool looping;

  @override
  State<AssetVideo> createState() => _AssetVideoState();
}

class _AssetVideoState extends State<AssetVideo> {
  late VideoPlayerController _controller;
  late Future<void> _initialization;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  @override
  void didUpdateWidget(AssetVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset == widget.asset) return;
    _controller.dispose();
    _initialize();
  }

  void _initialize() {
    _controller = VideoPlayerController.asset(widget.asset);
    _initialization = _controller.initialize().then((_) async {
      await _controller.setVolume(0);
      await _controller.setLooping(widget.looping);
      if (widget.autoplay) await _controller.play();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    if (!_controller.value.isInitialized) return;
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
      } else {
        _controller.play();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black,
      child: FutureBuilder<void>(
        future: _initialization,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(
              child: Icon(
                Icons.broken_image_outlined,
                color: Colors.white54,
                size: 42,
              ),
            );
          }
          if (!_controller.value.isInitialized) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.white70),
            );
          }

          final video = SizedBox(
            width: _controller.value.size.width,
            height: _controller.value.size.height,
            child: VideoPlayer(_controller),
          );
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _togglePlayback,
            child: ClipRect(
              child: FittedBox(fit: widget.fit, child: video),
            ),
          );
        },
      ),
    );
  }
}
