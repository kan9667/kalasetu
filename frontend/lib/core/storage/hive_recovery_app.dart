import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'hive_box_manager.dart';

/// Fail-closed recovery application shown when safety-critical Hive boxes fail to open.
///
/// Invariant: In data protection mode, no empty boxes are opened, no corrupted files are deleted,
/// and all background synchronization is halted until data is restored.
class HiveRecoveryApp extends StatelessWidget {
  final HiveRecoveryReport report;

  const HiveRecoveryApp({super.key, required this.report});

  @override
  Widget build(BuildContext context) {
    final boxName = report.failedBox ?? 'Unknown Box';
    final quarantinedPath = report.quarantinedPath ?? 'Unavailable';
    final error = report.error ?? 'Unknown error';

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: const Color(0xFFF9F6F0), // Parchment
        fontFamily: 'Inter',
      ),
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 32.0),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Warning Icon
                    Container(
                      width: 72,
                      height: 72,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFDF0ED), // Terracotta tint
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.shield_outlined,
                        size: 40,
                        color: Color(0xFFC85A32), // Terracotta
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Title
                    const Text(
                      'Data Protection Mode Active',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF2C2523),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'डेटा सुरक्षा मोड सक्रिय है',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF7A6E65),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Description
                    const Text(
                      'A safety-critical local storage box failed data integrity validation. '
                      'To prevent silent data loss, the box has NOT been deleted or replaced with an empty box. '
                      'Background synchronization has been halted.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 14,
                        color: Color(0xFF554A42),
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Quarantine details card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5DDD0)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'PROTECTED STORAGE DETAILS',
                            style: TextStyle(
                              fontSize: 11,
                              letterSpacing: 0.8,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF7A6E65),
                            ),
                          ),
                          const Divider(height: 20, color: Color(0xFFE5DDD0)),
                          _buildDetailRow('Affected Box:', boxName),
                          const SizedBox(height: 8),
                          _buildDetailRow('Quarantine Backup:', quarantinedPath),
                          const SizedBox(height: 8),
                          _buildDetailRow('Diagnostic Reason:', error),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Actions
                    ElevatedButton.icon(
                      onPressed: () {
                        Clipboard.setData(ClipboardData(text: quarantinedPath));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Quarantine path copied to clipboard'),
                            backgroundColor: Color(0xFF2C2523),
                          ),
                        );
                      },
                      icon: const Icon(Icons.copy, size: 18),
                      label: const Text('Copy Quarantine File Path'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFC85A32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () {
                        // Reset and let app attempt safe restart
                        HiveBoxManager.resetState();
                        SystemNavigator.pop();
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF2C2523),
                        side: const BorderSide(color: Color(0xFFD4C8B8)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: const Text('Close App Safely'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF7A6E65),
          ),
        ),
        const SizedBox(height: 2),
        SelectableText(
          value,
          style: const TextStyle(
            fontSize: 12,
            fontFamily: 'monospace',
            color: Color(0xFF2C2523),
          ),
        ),
      ],
    );
  }
}
