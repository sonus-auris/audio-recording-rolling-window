import '../models/app_config.dart';
import '../models/cloud_secrets.dart';
import '../models/playback_snapshot.dart';
import '../models/recorder_snapshot.dart';
import '../models/recording_segment.dart';
import '../models/storage_estimate.dart';

class AppViewModel {
  const AppViewModel({
    required this.config,
    required this.secrets,
    required this.segments,
    required this.recorder,
    required this.playback,
    required this.isInitializing,
    required this.isUploading,
    this.message,
  });

  final AppConfig config;
  final CloudSecrets secrets;
  final List<RecordingSegment> segments;
  final RecorderSnapshot recorder;
  final PlaybackSnapshot playback;
  final bool isInitializing;
  final bool isUploading;
  final String? message;

  StorageEstimate get estimate => StorageEstimate(
    bitRate: config.bitRate,
    deviceHours: config.deviceRetentionHours,
    cloudHours: config.cloudRetentionHours,
  );

  List<RecordingSegment> get localSegments =>
      segments.where((segment) => segment.isLocal).toList();

  int get localBytes =>
      localSegments.fold(0, (total, segment) => total + segment.byteSize);

  int get cloudBytes => segments
      .where((segment) => segment.isUploaded)
      .fold(0, (total, segment) => total + segment.byteSize);

  int get pendingUploads => segments
      .where(
        (segment) =>
            segment.uploadStatus == SegmentUploadStatus.pending ||
            segment.uploadStatus == SegmentUploadStatus.failed,
      )
      .length;

  int get failedUploads => segments
      .where((segment) => segment.uploadStatus == SegmentUploadStatus.failed)
      .length;

  int get uploadedSegments =>
      segments.where((segment) => segment.isUploaded).length;

  Duration get indexedDuration {
    return segments.fold(
      Duration.zero,
      (total, segment) => total + segment.duration,
    );
  }

  bool get canUploadToSelectedProvider {
    if (!config.uploadEnabled || !config.cloudProvider.isImplemented) {
      return false;
    }
    return config.s3TargetReady && secrets.hasS3Credentials;
  }
}
