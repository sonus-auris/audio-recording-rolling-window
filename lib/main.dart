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
          useMaterial3: true,
          inputDecorationTheme: const InputDecorationTheme(
            border: OutlineInputBorder(),
            isDense: true,
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
  final _bitRateController = TextEditingController();
  final _sampleRateController = TextEditingController();
  final _channelsController = TextEditingController();
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

  @override
  void dispose() {
    for (final controller in [
      _deviceRetentionController,
      _cloudRetentionController,
      _segmentMinutesController,
      _bitRateController,
      _sampleRateController,
      _channelsController,
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
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                children: [
                  if (viewModel.message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: MaterialBanner(
                        content: Text(viewModel.message!),
                        leading: const Icon(Icons.info_outline),
                        actions: [
                          TextButton(
                            onPressed: widget.controller.clearMessage,
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    ),
                  _StatusSection(
                    viewModel: viewModel,
                    onStart: widget.controller.startRecording,
                    onStop: widget.controller.stopRecording,
                    onPlay: widget.controller.playLocalWindow,
                    onPausePlayback: widget.controller.pausePlayback,
                    onStopPlayback: widget.controller.stopPlayback,
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 840;
                      final children = [
                        _CaptureSection(
                          deviceId: viewModel.config.deviceId,
                          uploadEnabled: _uploadEnabled,
                          onUploadEnabledChanged: (value) =>
                              setState(() => _uploadEnabled = value),
                          deviceRetentionController: _deviceRetentionController,
                          cloudRetentionController: _cloudRetentionController,
                          segmentMinutesController: _segmentMinutesController,
                          bitRateController: _bitRateController,
                          sampleRateController: _sampleRateController,
                          channelsController: _channelsController,
                        ),
                        _CloudSection(
                          selectedProvider: _selectedProvider,
                          onProviderChanged: (provider) =>
                              setState(() => _selectedProvider = provider),
                          s3BucketController: _s3BucketController,
                          s3RegionController: _s3RegionController,
                          s3PrefixController: _s3PrefixController,
                          s3EndpointController: _s3EndpointController,
                          s3AccessKeyController: _s3AccessKeyController,
                          s3SecretKeyController: _s3SecretKeyController,
                          s3SessionTokenController: _s3SessionTokenController,
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
                    onPressed: () => _save(viewModel),
                    icon: const Icon(Icons.save),
                    label: const Text('Save Configuration'),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
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
    _bitRateController.text = config.bitRate.toString();
    _sampleRateController.text = config.sampleRate.toString();
    _channelsController.text = config.channels.toString();
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
      bitRate: _parseInt(_bitRateController.text, 64000),
      sampleRate: _parseInt(_sampleRateController.text, 16000),
      channels: _parseInt(_channelsController.text, 1),
      uploadEnabled: _uploadEnabled,
      cloudProvider: _selectedProvider,
      s3Bucket: _s3BucketController.text,
      s3Region: _s3RegionController.text,
      s3Prefix: _s3PrefixController.text,
      s3Endpoint: _s3EndpointController.text,
    );
    final secrets = CloudSecrets(
      s3AccessKeyId: _s3AccessKeyController.text,
      s3SecretAccessKey: _s3SecretKeyController.text,
      s3SessionToken: _s3SessionTokenController.text,
    );
    await widget.controller.saveConfig(config);
    await widget.controller.saveSecrets(secrets);
    _syncedDeviceId = null;
  }

  int _parseInt(String value, int fallback) {
    return int.tryParse(value.trim()) ?? fallback;
  }
}

class _StatusSection extends StatelessWidget {
  const _StatusSection({
    required this.viewModel,
    required this.onStart,
    required this.onStop,
    required this.onPlay,
    required this.onPausePlayback,
    required this.onStopPlayback,
  });

  final AppViewModel viewModel;
  final VoidCallback onStart;
  final VoidCallback onStop;
  final VoidCallback onPlay;
  final VoidCallback onPausePlayback;
  final VoidCallback onStopPlayback;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final recorder = viewModel.recorder;
    final peak = ((recorder.peakDb + 60) / 60).clamp(0.0, 1.0);
    return _Section(
      title: 'Status',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                recorder.isRecording ? Icons.mic : Icons.mic_off,
                color: recorder.isRecording
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outline,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  recorder.isRecording ? 'Recording' : 'Stopped',
                  style: theme.textTheme.titleLarge,
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
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              minHeight: 8,
              value: peak,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
            ),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetricChip(
                icon: Icons.phone_android,
                label: 'Local',
                value: StorageEstimate.formatBytes(viewModel.localBytes),
              ),
              _MetricChip(
                icon: Icons.cloud_done,
                label: 'Cloud',
                value: StorageEstimate.formatBytes(viewModel.cloudBytes),
              ),
              _MetricChip(
                icon: Icons.schedule,
                label: 'Indexed',
                value: StorageEstimate.formatDurationHours(
                  viewModel.indexedDuration.inMinutes / 60,
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
                onPressed: viewModel.localSegments.isEmpty ? null : onPlay,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play Local Window'),
              ),
              if (viewModel.playback.isPlaying)
                IconButton.outlined(
                  tooltip: 'Pause playback',
                  onPressed: onPausePlayback,
                  icon: const Icon(Icons.pause),
                ),
              IconButton.outlined(
                tooltip: 'Stop playback',
                onPressed: viewModel.playback.isLoaded ? onStopPlayback : null,
                icon: const Icon(Icons.stop_circle_outlined),
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
    required this.bitRateController,
    required this.sampleRateController,
    required this.channelsController,
  });

  final String deviceId;
  final bool uploadEnabled;
  final ValueChanged<bool> onUploadEnabledChanged;
  final TextEditingController deviceRetentionController;
  final TextEditingController cloudRetentionController;
  final TextEditingController segmentMinutesController;
  final TextEditingController bitRateController;
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
          _NumberField(controller: bitRateController, label: 'Bitrate bps'),
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
          if (!selectedProvider.isImplemented)
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'This provider can be saved here; uploads currently run through S3.',
              ),
            ),
          if (!selectedProvider.isImplemented) const SizedBox(height: 12),
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

class _NumberField extends StatelessWidget {
  const _NumberField({required this.controller, required this.label});

  final TextEditingController controller;
  final String label;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      decoration: InputDecoration(labelText: label),
      keyboardType: TextInputType.number,
      validator: (value) {
        final parsed = int.tryParse(value?.trim() ?? '');
        if (parsed == null || parsed <= 0) {
          return 'Use a positive number';
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 8),
          Text('$label: ', style: theme.textTheme.labelLarge),
          Text(value),
        ],
      ),
    );
  }
}
