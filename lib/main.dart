import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

import 'src/app/app_controller.dart';
import 'src/app/app_view_model.dart';
import 'src/models/cloud_provider.dart';
import 'src/models/cloud_secrets.dart';
import 'src/models/storage_estimate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterForegroundTask.initCommunicationPort();
  runApp(const AudioDashcamRoot());
}

class AudioDashcamRoot extends StatefulWidget {
  const AudioDashcamRoot({super.key});

  @override
  State<AudioDashcamRoot> createState() => _AudioDashcamRootState();
}

class _AudioDashcamRootState extends State<AudioDashcamRoot> {
  late final AppController _controller;
  late final Future<void> _initFuture;

  @override
  void initState() {
    super.initState();
    _controller = AppController();
    _initFuture = _controller.init();
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return WithForegroundTask(
      child: MaterialApp(
        title: 'Audio Dashcam',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF287C66),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF6F8F7),
          useMaterial3: true,
          appBarTheme: const AppBarTheme(
            centerTitle: false,
            elevation: 0,
            scrolledUnderElevation: 0,
          ),
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            isDense: true,
          ),
          filledButtonTheme: FilledButtonThemeData(
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          outlinedButtonTheme: OutlinedButtonThemeData(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          cardTheme: const CardThemeData(margin: EdgeInsets.zero, elevation: 0),
        ),
        home: FutureBuilder<void>(
          future: _initFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const LoadingPage();
            }
            if (snapshot.hasError) {
              return ErrorPage(error: snapshot.error.toString());
            }
            return SettingsPage(controller: _controller);
          },
        ),
      ),
    );
  }
}

class LoadingPage extends StatelessWidget {
  const LoadingPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class ErrorPage extends StatelessWidget {
  const ErrorPage({super.key, required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Audio Dashcam')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error, textAlign: TextAlign.center),
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.controller});

  final AppController controller;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final _formKey = GlobalKey<FormState>();
  final _deviceRetentionController = TextEditingController();
  final _cloudRetentionController = TextEditingController();
  final _segmentMinutesController = TextEditingController();
  final _overlapSecondsController = TextEditingController();
  final _sampleRateController = TextEditingController();
  final _channelsController = TextEditingController();
  final _backendUrlController = TextEditingController();
  final _backendDeviceTokenController = TextEditingController();
  final _s3BucketController = TextEditingController();
  final _s3RegionController = TextEditingController();
  final _s3PrefixController = TextEditingController();
  final _s3EndpointController = TextEditingController();
  final _s3AccessKeyController = TextEditingController();
  final _s3SecretKeyController = TextEditingController();
  final _s3SessionTokenController = TextEditingController();

  String? _syncedDeviceId;
  CloudProvider _selectedProvider = CloudProvider.s3;
  bool _uploadEnabled = true;
  int _selectedIndex = 0;

  @override
  void dispose() {
    for (final controller in [
      _deviceRetentionController,
      _cloudRetentionController,
      _segmentMinutesController,
      _overlapSecondsController,
      _sampleRateController,
      _channelsController,
      _backendUrlController,
      _backendDeviceTokenController,
      _s3BucketController,
      _s3RegionController,
      _s3PrefixController,
      _s3EndpointController,
      _s3AccessKeyController,
      _s3SecretKeyController,
      _s3SessionTokenController,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AppViewModel>(
      stream: widget.controller.viewModels,
      builder: (context, snapshot) {
        final viewModel = snapshot.data;
        if (viewModel == null || viewModel.isInitializing) {
          return const LoadingPage();
        }
        _syncForm(viewModel);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Audio Dashcam'),
            actions: [
              IconButton(
                tooltip: 'Retry uploads',
                onPressed: viewModel.isUploading
                    ? null
                    : widget.controller.requestUploadDrain,
                icon: const Icon(Icons.cloud_sync),
              ),
            ],
          ),
          body: SafeArea(
            child: Column(
              children: [
                if (viewModel.message != null)
                  MaterialBanner(
                    content: Text(viewModel.message!),
                    leading: const Icon(Icons.info_outline),
                    actions: [
                      TextButton(
                        onPressed: widget.controller.clearMessage,
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                Expanded(child: _selectedBody(viewModel)),
              ],
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (index) =>
                setState(() => _selectedIndex = index),
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.dashboard_outlined),
                selectedIcon: Icon(Icons.dashboard),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.graphic_eq),
                selectedIcon: Icon(Icons.graphic_eq),
                label: 'Playback',
              ),
              NavigationDestination(
                icon: Icon(Icons.tune),
                selectedIcon: Icon(Icons.tune),
                label: 'Configure',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _selectedBody(AppViewModel viewModel) {
    switch (_selectedIndex) {
      case 1:
        return _PlaybackView(
          viewModel: viewModel,
          onPlay: widget.controller.playLocalWindow,
          onPausePlayback: widget.controller.pausePlayback,
          onStopPlayback: widget.controller.stopPlayback,
          onSendAlert: widget.controller.sendManualAlert,
        );
      case 2:
        return Form(
          key: _formKey,
          child: _ConfigureView(
            viewModel: viewModel,
            selectedProvider: _selectedProvider,
            uploadEnabled: _uploadEnabled,
            onUploadEnabledChanged: (value) =>
                setState(() => _uploadEnabled = value),
            onProviderChanged: (provider) =>
                setState(() => _selectedProvider = provider),
            onSave: () => _save(viewModel),
            deviceRetentionController: _deviceRetentionController,
            cloudRetentionController: _cloudRetentionController,
            segmentMinutesController: _segmentMinutesController,
            overlapSecondsController: _overlapSecondsController,
            sampleRateController: _sampleRateController,
            channelsController: _channelsController,
            backendUrlController: _backendUrlController,
            backendDeviceTokenController: _backendDeviceTokenController,
            s3BucketController: _s3BucketController,
            s3RegionController: _s3RegionController,
            s3PrefixController: _s3PrefixController,
            s3EndpointController: _s3EndpointController,
            s3AccessKeyController: _s3AccessKeyController,
            s3SecretKeyController: _s3SecretKeyController,
            s3SessionTokenController: _s3SessionTokenController,
          ),
        );
      default:
        return _HomeView(
          viewModel: viewModel,
          onStart: widget.controller.startRecording,
          onStop: widget.controller.stopRecording,
          onSendAlert: widget.controller.sendManualAlert,
        );
    }
  }

  void _syncForm(AppViewModel viewModel) {
    if (_syncedDeviceId == viewModel.config.deviceId) {
      return;
    }
    final config = viewModel.config;
    final secrets = viewModel.secrets;
    _deviceRetentionController.text = config.deviceRetentionHours.toString();
    _cloudRetentionController.text = config.cloudRetentionHours.toString();
    _segmentMinutesController.text = config.segmentMinutes.toString();
    _overlapSecondsController.text = config.overlapSeconds.toString();
    _sampleRateController.text = config.sampleRate.toString();
    _channelsController.text = config.channels.toString();
    _backendUrlController.text = config.backendBaseUrl;
    _backendDeviceTokenController.text = secrets.backendDeviceToken;
    _s3BucketController.text = config.s3Bucket;
    _s3RegionController.text = config.s3Region;
    _s3PrefixController.text = config.s3Prefix;
    _s3EndpointController.text = config.s3Endpoint;
    _s3AccessKeyController.text = secrets.s3AccessKeyId;
    _s3SecretKeyController.text = secrets.s3SecretAccessKey;
    _s3SessionTokenController.text = secrets.s3SessionToken;
    _selectedProvider = config.cloudProvider;
    _uploadEnabled = config.uploadEnabled;
    _syncedDeviceId = config.deviceId;
  }

  Future<void> _save(AppViewModel viewModel) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final config = viewModel.config.copyWith(
      deviceRetentionHours: _parseInt(_deviceRetentionController.text, 50),
      cloudRetentionHours: _parseInt(_cloudRetentionController.text, 500),
      segmentMinutes: _parseInt(_segmentMinutesController.text, 1),
      overlapSeconds: _parseInt(_overlapSecondsController.text, 2),
      sampleRate: _parseInt(_sampleRateController.text, 16000),
      channels: _parseInt(_channelsController.text, 1),
      uploadEnabled: _uploadEnabled,
      cloudProvider: _selectedProvider,
      backendBaseUrl: _backendUrlController.text,
      s3Bucket: _s3BucketController.text,
      s3Region: _s3RegionController.text,
      s3Prefix: _s3PrefixController.text,
      s3Endpoint: _s3EndpointController.text,
    );
    final secrets = CloudSecrets(
      s3AccessKeyId: _s3AccessKeyController.text,
      s3SecretAccessKey: _s3SecretKeyController.text,
      s3SessionToken: _s3SessionTokenController.text,
      backendDeviceToken: _backendDeviceTokenController.text,
    );
    await widget.controller.saveConfig(config);
    await widget.controller.saveSecrets(secrets);
    _syncedDeviceId = null;
  }

  int _parseInt(String value, int fallback) {
    return int.tryParse(value.trim()) ?? fallback;
  }
}

class _HomeView extends StatelessWidget {
  const _HomeView({
    required this.viewModel,
    required this.onStart,
    required this.onStop,
    required this.onSendAlert,
  });

  final AppViewModel viewModel;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onSendAlert;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _StatusSection(
          viewModel: viewModel,
          onStart: onStart,
          onStop: onStop,
          onSendAlert: onSendAlert,
        ),
        const SizedBox(height: 16),
        _DiagnosticsSection(entries: viewModel.diagnosticEntries),
      ],
    );
  }
}

class _PlaybackView extends StatelessWidget {
  const _PlaybackView({
    required this.viewModel,
    required this.onPlay,
    required this.onPausePlayback,
    required this.onStopPlayback,
    required this.onSendAlert,
  });

  final AppViewModel viewModel;
  final VoidCallback onPlay;
  final VoidCallback onPausePlayback;
  final VoidCallback onStopPlayback;
  final VoidCallback onSendAlert;

  @override
  Widget build(BuildContext context) {
    final playback = viewModel.playback;
    final recent = viewModel.localSegments.reversed.take(12).toList();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        _Section(
          title: 'Playback',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: viewModel.localSegments.isEmpty ? null : onPlay,
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play Local Window'),
                  ),
                  if (playback.isPlaying)
                    IconButton.outlined(
                      tooltip: 'Pause playback',
                      onPressed: onPausePlayback,
                      icon: const Icon(Icons.pause),
                    ),
                  IconButton.outlined(
                    tooltip: 'Stop playback',
                    onPressed: playback.isLoaded ? onStopPlayback : null,
                    icon: const Icon(Icons.stop_circle_outlined),
                  ),
                  OutlinedButton.icon(
                    onPressed: onSendAlert,
                    icon: const Icon(Icons.notification_important_outlined),
                    label: const Text('Send Alert'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricChip(
                    icon: Icons.timer_outlined,
                    label: 'Position',
                    value: _formatDuration(playback.position),
                  ),
                  _MetricChip(
                    icon: Icons.timeline,
                    label: 'Gaps',
                    value: viewModel.continuityGapCount.toString(),
                  ),
                  _MetricChip(
                    icon: Icons.join_inner,
                    label: 'Overlapped',
                    value: viewModel.overlappedSegments.toString(),
                  ),
                ],
              ),
              if (playback.error != null) ...[
                const SizedBox(height: 12),
                Text(
                  playback.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        _Section(
          title: 'Local Segments',
          child: Column(
            children: [
              if (recent.isEmpty)
                _InlineState(
                  icon: Icons.hourglass_empty,
                  text: viewModel.recorder.isRecording
                      ? 'First segment is still recording.'
                      : 'No local segments yet.',
                )
              else
                for (final segment in recent)
                  _SegmentListItem(
                    title: segment.startedAtUtc.toLocal().toString(),
                    subtitle:
                        '${_formatDuration(segment.canonicalDuration)}'
                        ' / overlap ${_formatDuration(segment.trimStart)}',
                    trailing: StorageEstimate.formatBytes(segment.byteSize),
                  ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }
}

class _ConfigureView extends StatelessWidget {
  const _ConfigureView({
    required this.viewModel,
    required this.selectedProvider,
    required this.uploadEnabled,
    required this.onUploadEnabledChanged,
    required this.onProviderChanged,
    required this.onSave,
    required this.deviceRetentionController,
    required this.cloudRetentionController,
    required this.segmentMinutesController,
    required this.overlapSecondsController,
    required this.sampleRateController,
    required this.channelsController,
    required this.backendUrlController,
    required this.backendDeviceTokenController,
    required this.s3BucketController,
    required this.s3RegionController,
    required this.s3PrefixController,
    required this.s3EndpointController,
    required this.s3AccessKeyController,
    required this.s3SecretKeyController,
    required this.s3SessionTokenController,
  });

  final AppViewModel viewModel;
  final CloudProvider selectedProvider;
  final bool uploadEnabled;
  final ValueChanged<bool> onUploadEnabledChanged;
  final ValueChanged<CloudProvider> onProviderChanged;
  final VoidCallback onSave;
  final TextEditingController deviceRetentionController;
  final TextEditingController cloudRetentionController;
  final TextEditingController segmentMinutesController;
  final TextEditingController overlapSecondsController;
  final TextEditingController sampleRateController;
  final TextEditingController channelsController;
  final TextEditingController backendUrlController;
  final TextEditingController backendDeviceTokenController;
  final TextEditingController s3BucketController;
  final TextEditingController s3RegionController;
  final TextEditingController s3PrefixController;
  final TextEditingController s3EndpointController;
  final TextEditingController s3AccessKeyController;
  final TextEditingController s3SecretKeyController;
  final TextEditingController s3SessionTokenController;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 840;
            final children = [
              _CaptureSection(
                deviceId: viewModel.config.deviceId,
                uploadEnabled: uploadEnabled,
                onUploadEnabledChanged: onUploadEnabledChanged,
                deviceRetentionController: deviceRetentionController,
                cloudRetentionController: cloudRetentionController,
                segmentMinutesController: segmentMinutesController,
                overlapSecondsController: overlapSecondsController,
                sampleRateController: sampleRateController,
                channelsController: channelsController,
              ),
              _CloudSection(
                selectedProvider: selectedProvider,
                onProviderChanged: onProviderChanged,
                backendUrlController: backendUrlController,
                backendDeviceTokenController: backendDeviceTokenController,
                s3BucketController: s3BucketController,
                s3RegionController: s3RegionController,
                s3PrefixController: s3PrefixController,
                s3EndpointController: s3EndpointController,
                s3AccessKeyController: s3AccessKeyController,
                s3SecretKeyController: s3SecretKeyController,
                s3SessionTokenController: s3SessionTokenController,
              ),
            ];
            if (!wide) {
              return Column(
                children: [
                  children.first,
                  const SizedBox(height: 16),
                  children.last,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: children.first),
                const SizedBox(width: 16),
                Expanded(child: children.last),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: onSave,
          icon: const Icon(Icons.save),
          label: const Text('Save Configuration'),
        ),
      ],
    );
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({
    required this.viewModel,
    required this.onStart,
    required this.onStop,
    required this.onSendAlert,
  });

  final AppViewModel viewModel;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onSendAlert;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recorder = viewModel.recorder;
    final peak = ((recorder.peakDb + 60) / 60).clamp(0.0, 1.0);
    final localCapacitySeconds = viewModel.config.deviceRetentionHours * 3600;
    final localProgress = localCapacitySeconds <= 0
        ? 0.0
        : (viewModel.localWindowDuration.inSeconds / localCapacitySeconds)
              .clamp(0.0, 1.0);
    final statusColor = recorder.isRecording
        ? theme.colorScheme.primary
        : theme.colorScheme.outline;
    return _Section(
      title: 'Live Capture',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  recorder.isRecording ? Icons.mic : Icons.mic_off,
                  color: statusColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      recorder.isRecording ? 'Recording' : 'Stopped',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      recorder.isRecording
                          ? _formatDuration(viewModel.activeRecordingDuration)
                          : '${viewModel.config.deviceRetentionHours} h local window',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (viewModel.isUploading)
                const SizedBox.square(
                  dimension: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Text('Input level', style: theme.textTheme.labelLarge),
              const Spacer(),
              Text(
                '${recorder.peakDb.toStringAsFixed(0)} dB',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: peak,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 16),
          _RetentionBar(
            label: 'Local retention',
            value: localProgress,
            leadingValue: _formatDuration(viewModel.localWindowDuration),
            trailingValue: '${viewModel.config.deviceRetentionHours} h',
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _MetricChip(
                icon: Icons.phone_android,
                label: 'Local',
                value: StorageEstimate.formatBytes(viewModel.localWindowBytes),
              ),
              _MetricChip(
                icon: Icons.cloud_done,
                label: 'Cloud',
                value: StorageEstimate.formatBytes(viewModel.cloudBytes),
              ),
              _MetricChip(
                icon: Icons.schedule,
                label: 'Local window',
                value: StorageEstimate.formatDurationHours(
                  viewModel.localWindowDuration.inSeconds / 3600,
                ),
              ),
              _MetricChip(
                icon: Icons.pending_actions,
                label: 'Pending',
                value: viewModel.pendingUploads.toString(),
              ),
              _MetricChip(
                icon: Icons.sd_storage,
                label: '500 h estimate',
                value: StorageEstimate.formatBytes(
                  viewModel.estimate.cloudBytes,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: recorder.isRecording || recorder.isStarting
                    ? null
                    : onStart,
                icon: const Icon(Icons.fiber_manual_record),
                label: const Text('Start'),
              ),
              OutlinedButton.icon(
                onPressed: recorder.isRecording || recorder.isStarting
                    ? onStop
                    : null,
                icon: const Icon(Icons.stop),
                label: const Text('Stop'),
              ),
              OutlinedButton.icon(
                onPressed: onSendAlert,
                icon: const Icon(Icons.notification_important_outlined),
                label: const Text('Send Alert'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CaptureSection extends StatelessWidget {
  const _CaptureSection({
    required this.deviceId,
    required this.uploadEnabled,
    required this.onUploadEnabledChanged,
    required this.deviceRetentionController,
    required this.cloudRetentionController,
    required this.segmentMinutesController,
    required this.overlapSecondsController,
    required this.sampleRateController,
    required this.channelsController,
  });

  final String deviceId;
  final bool uploadEnabled;
  final ValueChanged<bool> onUploadEnabledChanged;
  final TextEditingController deviceRetentionController;
  final TextEditingController cloudRetentionController;
  final TextEditingController segmentMinutesController;
  final TextEditingController overlapSecondsController;
  final TextEditingController sampleRateController;
  final TextEditingController channelsController;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Capture',
      child: Column(
        children: [
          SelectableText('Device ID: $deviceId'),
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: uploadEnabled,
            onChanged: onUploadEnabledChanged,
            title: const Text('Cloud upload'),
          ),
          _NumberField(
            controller: deviceRetentionController,
            label: 'Local retention hours',
          ),
          const SizedBox(height: 12),
          _NumberField(
            controller: cloudRetentionController,
            label: 'Cloud retention hours',
          ),
          const SizedBox(height: 12),
          _NumberField(
            controller: segmentMinutesController,
            label: 'Segment minutes',
          ),
          const SizedBox(height: 12),
          _NumberField(
            controller: overlapSecondsController,
            label: 'Overlap seconds',
            allowZero: true,
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _NumberField(
                  controller: sampleRateController,
                  label: 'Sample rate',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberField(
                  controller: channelsController,
                  label: 'Channels',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CloudSection extends StatelessWidget {
  const _CloudSection({
    required this.selectedProvider,
    required this.onProviderChanged,
    required this.backendUrlController,
    required this.backendDeviceTokenController,
    required this.s3BucketController,
    required this.s3RegionController,
    required this.s3PrefixController,
    required this.s3EndpointController,
    required this.s3AccessKeyController,
    required this.s3SecretKeyController,
    required this.s3SessionTokenController,
  });

  final CloudProvider selectedProvider;
  final ValueChanged<CloudProvider> onProviderChanged;
  final TextEditingController backendUrlController;
  final TextEditingController backendDeviceTokenController;
  final TextEditingController s3BucketController;
  final TextEditingController s3RegionController;
  final TextEditingController s3PrefixController;
  final TextEditingController s3EndpointController;
  final TextEditingController s3AccessKeyController;
  final TextEditingController s3SecretKeyController;
  final TextEditingController s3SessionTokenController;

  @override
  Widget build(BuildContext context) {
    return _Section(
      title: 'Cloud',
      child: Column(
        children: [
          DropdownButtonFormField<CloudProvider>(
            initialValue: selectedProvider,
            decoration: const InputDecoration(labelText: 'Provider'),
            items: CloudProvider.values
                .map(
                  (provider) => DropdownMenuItem(
                    value: provider,
                    child: Text(provider.label),
                  ),
                )
                .toList(),
            onChanged: (provider) {
              if (provider != null) {
                onProviderChanged(provider);
              }
            },
          ),
          const SizedBox(height: 12),
          if (selectedProvider.requiresBackend)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'This provider uploads through the sound recorder backend.',
              ),
            ),
          if (selectedProvider.requiresBackend) const SizedBox(height: 12),
          TextFormField(
            controller: backendUrlController,
            decoration: const InputDecoration(labelText: 'Backend URL'),
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.url,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: backendDeviceTokenController,
            decoration: const InputDecoration(
              labelText: 'Backend device token',
            ),
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: s3BucketController,
            decoration: const InputDecoration(labelText: 'S3 bucket'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: s3RegionController,
            decoration: const InputDecoration(labelText: 'S3 region'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: s3PrefixController,
            decoration: const InputDecoration(labelText: 'S3 prefix'),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: s3EndpointController,
            decoration: const InputDecoration(
              labelText: 'S3-compatible endpoint',
            ),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: s3AccessKeyController,
            decoration: const InputDecoration(labelText: 'S3 access key ID'),
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: s3SecretKeyController,
            decoration: const InputDecoration(
              labelText: 'S3 secret access key',
            ),
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: s3SessionTokenController,
            decoration: const InputDecoration(labelText: 'S3 session token'),
            obscureText: true,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: TextInputType.visiblePassword,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}

class _DiagnosticsSection extends StatelessWidget {
  const _DiagnosticsSection({required this.entries});

  final List<String> entries;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recent = entries.take(24).join('\n');
    final latest = entries.isEmpty ? 'No diagnostics yet.' : entries.first;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
        collapsedShape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
        ),
        leading: const Icon(Icons.terminal),
        title: const Text('Diagnostics'),
        subtitle: Text(latest, maxLines: 1, overflow: TextOverflow.ellipsis),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: SelectableText(
              recent.isEmpty ? 'No diagnostics yet.' : recent,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFeatures: const [],
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RetentionBar extends StatelessWidget {
  const _RetentionBar({
    required this.label,
    required this.value,
    required this.leadingValue,
    required this.trailingValue,
  });

  final String label;
  final double value;
  final String leadingValue;
  final String trailingValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: theme.textTheme.labelLarge),
            const Spacer(),
            Text(
              '$leadingValue / $trailingValue',
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            minHeight: 8,
            value: value,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
          ),
        ),
      ],
    );
  }
}

class _SegmentListItem extends StatelessWidget {
  const _SegmentListItem({
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(Icons.audio_file_outlined, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(trailing, style: theme.textTheme.labelLarge),
        ],
      ),
    );
  }
}

class _InlineState extends StatelessWidget {
  const _InlineState({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.controller,
    required this.label,
    this.allowZero = false,
  });

  final TextEditingController controller;
  final String label;
  final bool allowZero;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.number,
      validator: (value) {
        final parsed = int.tryParse(value?.trim() ?? '');
        if (parsed == null || parsed < 0 || (!allowZero && parsed == 0)) {
          return allowZero
              ? 'Use zero or a positive number'
              : 'Use a positive number';
        }
        return null;
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 148, minHeight: 64),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLowest,
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 20, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}
