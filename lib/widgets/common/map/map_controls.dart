import 'package:flutter/material.dart';

typedef SourceChanged = void Function(int source);

class MapControls extends StatelessWidget {
  final int source; // 0=local,1=all,2=global
  final SourceChanged? onSourceChanged;
  final bool showSourceControl;
  final bool showHeatmapControl;
  final bool showFullScreenControl;
  final bool showHeatmapState;
  final VoidCallback? onToggleHeatmap;
  final VoidCallback? onFullScreen;
  final bool loadingGlobal;

  const MapControls({
    super.key,
    this.source = 0,
    this.onSourceChanged,
    this.showSourceControl = true,
    this.showHeatmapControl = true,
    this.showFullScreenControl = true,
    this.showHeatmapState = false,
    this.onToggleHeatmap,
    this.onFullScreen,
    this.loadingGlobal = false,
  });

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = [];

    if (showSourceControl && onSourceChanged != null) {
      children.add(
        Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: PopupMenuButton<int>(
            initialValue: source,
            tooltip: 'Pothole source',
            color: Colors.grey[900],
            onSelected: onSourceChanged,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    source == 2
                        ? Icons.cloud_done
                        : (source == 1 ? Icons.layers : Icons.phone_android),
                    size: 18,
                    color: Colors.white70,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    source == 0 ? 'Local' : (source == 1 ? 'All' : 'Global'),
                    style: const TextStyle(fontSize: 12, color: Colors.white70),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.arrow_drop_down,
                    color: Colors.white70,
                    size: 18,
                  ),
                ],
              ),
            ),
            itemBuilder: (ctx) => const [
              PopupMenuItem(
                value: 0,
                child: Text('Local', style: TextStyle(color: Colors.white70)),
              ),
              PopupMenuItem(
                value: 1,
                child: Text('All', style: TextStyle(color: Colors.white70)),
              ),
              PopupMenuItem(
                value: 2,
                child: Text('Global', style: TextStyle(color: Colors.white70)),
              ),
            ],
          ),
        ),
      );
    }

    if (showHeatmapControl && onToggleHeatmap != null) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 8));
      children.add(
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            icon: Icon(
              showHeatmapState ? Icons.whatshot : Icons.blur_on,
              color: Colors.white70,
            ),
            tooltip: showHeatmapState ? 'Heatmap On' : 'Heatmap Off',
            onPressed: onToggleHeatmap,
          ),
        ),
      );
    }

    if (showFullScreenControl && onFullScreen != null) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 8));
      children.add(
        Container(
          height: 36,
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: IconButton(
            icon: const Icon(Icons.open_in_full, color: Colors.white70),
            tooltip: 'Full screen',
            onPressed: onFullScreen,
          ),
        ),
      );
    }

    if (loadingGlobal) {
      if (children.isNotEmpty) children.add(const SizedBox(width: 8));
      children.add(
        const SizedBox(
          height: 36,
          width: 36,
          child: Center(child: CircularProgressIndicator(strokeWidth: 2.0)),
        ),
      );
    }

    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }
}
