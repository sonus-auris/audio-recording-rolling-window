enum SegmentUploadStatus {
  pending,
  uploading,
  uploaded,
  failed,
  localOnly;

  static SegmentUploadStatus fromName(String? name) {
    return SegmentUploadStatus.values.firstWhere(
      (status) => status.name == name,
      orElse: () => SegmentUploadStatus.pending,
    );
  }
}

class RecordingSegment {
  const RecordingSegment({
    required this.id,
    required this.startedAtUtc,
    required this.endedAtUtc,
    required this.byteSize,
    required this.uploadStatus,
    this.localPath,
    this.remoteKey,
    this.uploadedAtUtc,
    this.error,
  });

  final String id;
  final DateTime startedAtUtc;
  final DateTime endedAtUtc;
  final String? localPath;
  final int byteSize;
  final SegmentUploadStatus uploadStatus;
  final String? remoteKey;
  final DateTime? uploadedAtUtc;
  final String? error;

  Duration get duration => endedAtUtc.difference(startedAtUtc);

  bool get isLocal => localPath != null && localPath!.isNotEmpty;

  bool get isUploaded => uploadStatus == SegmentUploadStatus.uploaded;

  RecordingSegment copyWith({
    String? id,
    DateTime? startedAtUtc,
    DateTime? endedAtUtc,
    Object? localPath = _unset,
    int? byteSize,
    SegmentUploadStatus? uploadStatus,
    Object? remoteKey = _unset,
    Object? uploadedAtUtc = _unset,
    Object? error = _unset,
  }) {
    return RecordingSegment(
      id: id ?? this.id,
      startedAtUtc: startedAtUtc ?? this.startedAtUtc,
      endedAtUtc: endedAtUtc ?? this.endedAtUtc,
      localPath: identical(localPath, _unset)
          ? this.localPath
          : localPath as String?,
      byteSize: byteSize ?? this.byteSize,
      uploadStatus: uploadStatus ?? this.uploadStatus,
      remoteKey: identical(remoteKey, _unset)
          ? this.remoteKey
          : remoteKey as String?,
      uploadedAtUtc: identical(uploadedAtUtc, _unset)
          ? this.uploadedAtUtc
          : uploadedAtUtc as DateTime?,
      error: identical(error, _unset) ? this.error : error as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'startedAtUtc': startedAtUtc.toIso8601String(),
      'endedAtUtc': endedAtUtc.toIso8601String(),
      'localPath': localPath,
      'byteSize': byteSize,
      'uploadStatus': uploadStatus.name,
      'remoteKey': remoteKey,
      'uploadedAtUtc': uploadedAtUtc?.toIso8601String(),
      'error': error,
    };
  }

  factory RecordingSegment.fromJson(Map<String, dynamic> json) {
    return RecordingSegment(
      id: json['id'] as String,
      startedAtUtc: DateTime.parse(json['startedAtUtc'] as String).toUtc(),
      endedAtUtc: DateTime.parse(json['endedAtUtc'] as String).toUtc(),
      localPath: json['localPath'] as String?,
      byteSize: _asInt(json['byteSize']),
      uploadStatus: SegmentUploadStatus.fromName(
        json['uploadStatus'] as String?,
      ),
      remoteKey: json['remoteKey'] as String?,
      uploadedAtUtc: json['uploadedAtUtc'] == null
          ? null
          : DateTime.parse(json['uploadedAtUtc'] as String).toUtc(),
      error: json['error'] as String?,
    );
  }

  static const _unset = Object();

  static int _asInt(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.round();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
