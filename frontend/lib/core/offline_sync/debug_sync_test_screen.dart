import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

import 'models/queue_item.dart';
import 'offline_sync_service.dart';

/// Throwaway screen for exercising the sync engine before any real UI
/// exists. Wire a button to it (or a debug-only route) — delete before
/// final submission, or gate it behind a "Debug Tools" flag for
/// demo-day troubleshooting.
class DebugSyncTestScreen extends StatefulWidget {
  const DebugSyncTestScreen({super.key, this.queueStream});

  final Stream<List<QueueItem>>? queueStream;

  @override
  State<DebugSyncTestScreen> createState() => _DebugSyncTestScreenState();
}

class _DebugSyncTestScreenState extends State<DebugSyncTestScreen> {
  final AudioRecorder _recorder = AudioRecorder();
  bool _isRecording = false;

  Future<void> _simulateImageCapture(BuildContext context) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final localId = await OfflineSyncService.instance.enqueueImage(
      imageFile: File(picked.path),
      productDraftId: 'debug-draft-${DateTime.now().millisecondsSinceEpoch}',
    );

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Queued image, localId: $localId')),
      );
    }
  }

  Future<void> _toggleVoiceRecording(BuildContext context) async {
    if (_isRecording) {
      final path = await _recorder.stop();
      if (!mounted) return;
      setState(() => _isRecording = false);
      if (path == null) return;

      final localId = await OfflineSyncService.instance.enqueueVoiceNote(
        audioFile: File(path),
        productDraftId: 'debug-draft-${DateTime.now().millisecondsSinceEpoch}',
      );
      await File(path).delete();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Queued voice note, localId: $localId')),
        );
      }
      return;
    }

    if (!await _recorder.hasPermission()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required.')),
        );
      }
      return;
    }

    final appDir = await getApplicationDocumentsDirectory();
    final recordingDir = Directory('${appDir.path}/offline_sync_recordings');
    await recordingDir.create(recursive: true);
    final path = '${recordingDir.path}/voice-${DateTime.now().millisecondsSinceEpoch}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc),
      path: path,
    );
    if (mounted) setState(() => _isRecording = true);
  }

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Color _statusColor(QueueStatus status) {
    switch (status) {
      case QueueStatus.pending:
        return Colors.amber;
      case QueueStatus.uploading:
      case QueueStatus.processing:
        return Colors.blue;
      case QueueStatus.completed:
        return Colors.green;
      case QueueStatus.failed:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Offline Sync — Debug')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: ElevatedButton.icon(
              icon: const Icon(Icons.camera_alt),
              label: const Text('Simulate image capture'),
              onPressed: () => _simulateImageCapture(context),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ElevatedButton.icon(
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              label: Text(_isRecording ? 'Stop and queue voice note' : 'Record voice note'),
              onPressed: () => _toggleVoiceRecording(context),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text(
              'Turn on airplane mode, tap the button a few times, then '
              'turn it back off and watch this list update on its own.',
              style: TextStyle(color: Colors.grey),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: StreamBuilder<List<QueueItem>>(
              stream: widget.queueStream ?? OfflineSyncService.instance.watchQueue(),
              builder: (context, snapshot) {
                final items = snapshot.data ?? [];
                if (items.isEmpty) {
                  return const Center(child: Text('Queue is empty.'));
                }
                return ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ListTile(
                      leading: CircleAvatar(backgroundColor: _statusColor(item.status)),
                      title: Text(item.type.name),
                      subtitle: Text(
                        '${item.status.name}'
                        '${item.retryCount > 0 ? ' · retry ${item.retryCount}' : ''}'
                        '${item.errorMessage != null ? '\n${item.errorMessage}' : ''}',
                      ),
                      isThreeLine: item.errorMessage != null,
                      trailing: item.status == QueueStatus.failed
                          ? IconButton(
                              icon: const Icon(Icons.refresh),
                              onPressed: () =>
                                  OfflineSyncService.instance.retryItem(item.localId),
                            )
                          : null,
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
