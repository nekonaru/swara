import 'package:flutter/material.dart';
import '../widgets/song_art_image.dart';
import '../services/player_service.dart';
import '../screens/player_screen.dart';
import '../utils/page_transitions.dart';

class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = PlayerService.instance;
    return AnimatedBuilder(
      animation: player,
      builder: (context, _) {
        final song = player.currentSong;
        if (song == null) return const SizedBox.shrink();
        return TweenAnimationBuilder<double>(
          key: ValueKey('mp_${song.id}'),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          builder: (context, value, child) => Transform.translate(
            offset: Offset(0, (1 - value) * 12),
            child: Opacity(opacity: value, child: child),
          ),
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            // Material plus InkWell keeps the tap to PlayerScreen
            // while adding a proper ripple feedback.
            child: InkWell(
              onTap: () => Navigator.push(
                context,
                SlideUpRoute(page: const PlayerScreen()),
              ),
              child: SizedBox(
                height: 64,
            child: Row(
              children: [
                const SizedBox(width: 8),
                // Same tag as the cover on the player screen, so opening the
                // player flies this artwork into the big cover instead of
                // swapping two unrelated pictures. A target without a matching
                // tag simply skips the flight, so nothing else can break.
                Hero(
                  tag: 'swara_art_${song.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SongArtImage(
                      song: song,
                      width: 44, height: 44, fit: BoxFit.cover,
                      // Decode thumbnail size only to save image memory.
                      cacheWidth: 88,
                      fallback: Container(
                        width: 44, height: 44, color: Colors.grey[400],
                        child: const Icon(Icons.music_note, size: 20),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.skip_previous),
                  onPressed: () {
                    player.previous().catchError((_) {});
                  },
                ),
                StreamBuilder(
                  // Key based on the active player so the StreamBuilder re-subscribes
                  // after a crossfade (player instance changes). Without this
                  // the play/pause icon gets stuck on the old state.
                  key: ValueKey(
                      'mp_state_${player.player.hashCode}_${song.id}'),
                  stream: player.player.playerStateStream,
                  builder: (context, snapshot) {
                    final playing =
                        snapshot.data?.playing ?? player.player.playing;
                    return IconButton(
                      icon: Icon(playing ? Icons.pause : Icons.play_arrow),
                      onPressed: () {
                        player.togglePlayPause().catchError((_) {});
                      },
                    );
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.skip_next),
                  onPressed: () {
                    player.next().catchError((_) {});
                  },
                ),
                const SizedBox(width: 4),
              ],
            ),
          ),
          ),
          ),
        );
      },
    );
  }
}
