import 'dart:async';

import 'package:just_audio/just_audio.dart';
import 'package:rxdart/rxdart.dart';

import '../models/playback_snapshot.dart';
import '../models/recording_segment.dart';

class PlaybackService {
  PlaybackService({AudioPlayer? player}) : _player = player ?? AudioPlayer() {
    _subscriptions.addAll([
      _player.playerStateStream.listen((state) {
        _emit(_snapshot.value.copyWith(isPlaying: state.playing));
      }),
      _player.positionStream.listen((position) {
        _emit(_snapshot.value.copyWith(position: position));
      }),
      _player.durationStream.listen((duration) {
        _emit(_snapshot.value.copyWith(duration: duration ?? Duration.zero));
      }),
      _player.currentIndexStream.listen((index) {
        _emit(_snapshot.value.copyWith(currentIndex: index));
      }),
    ]);
  }

  final AudioPlayer _player;
  final BehaviorSubject<PlaybackSnapshot> _snapshot = BehaviorSubject.seeded(
    const PlaybackSnapshot.empty(),
  );
  final List<StreamSubscription<dynamic>> _subscriptions = [];

  ValueStream<PlaybackSnapshot> get snapshots => _snapshot.stream;

  Future<void> playSegments(List<RecordingSegment> segments) async {
    final localSegments =
        segments.where((segment) => segment.localPath != null).toList()
          ..sort((a, b) => a.startedAtUtc.compareTo(b.startedAtUtc));
    if (localSegments.isEmpty) {
      _emit(
        const PlaybackSnapshot.empty().copyWith(
          error: 'No local audio segments are available.',
        ),
      );
      return;
    }
    try {
      await _player.setAudioSources(
        localSegments.map(_sourceForSegment).toList(),
        preload: true,
      );
      _emit(
        _snapshot.value.copyWith(isLoaded: true, error: null, currentIndex: 0),
      );
      await _player.play();
    } catch (error) {
      _emit(_snapshot.value.copyWith(error: error.toString()));
    }
  }

  Future<void> pause() => _player.pause();

  Future<void> stop() async {
    await _player.stop();
    _emit(const PlaybackSnapshot.empty());
  }

  Future<void> dispose() async {
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _snapshot.close();
    await _player.dispose();
  }

  void _emit(PlaybackSnapshot snapshot) {
    if (!_snapshot.isClosed) {
      _snapshot.add(snapshot);
    }
  }

  AudioSource _sourceForSegment(RecordingSegment segment) {
    final file = AudioSource.file(segment.localPath!, tag: segment.id);
    if (segment.trimStart <= Duration.zero) {
      return file;
    }
    return ClippingAudioSource(
      child: file,
      start: segment.trimStart,
      duration: segment.canonicalDuration,
      tag: segment.id,
    );
  }
}
