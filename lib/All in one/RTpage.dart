import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/dataset_record_model.dart';
import '../services/database_service.dart';
import '../widgets/empty_state_widget.dart';
import '../widgets/loading_widget.dart';

class RTpage extends StatelessWidget {
  const RTpage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = DatabaseService();

    return Scaffold(
      appBar: AppBar(title: const Text('My Submissions'), centerTitle: true),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: service.watchCurrentUserRecords(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const LoadingWidget();
          }
          if (snapshot.hasError) {
            return EmptyStateWidget(
              message: 'Could not load submissions: ${snapshot.error}',
            );
          }

          final records =
              (snapshot.data?.docs ?? [])
                  .map(DatasetRecordModel.fromFirestore)
                  .toList()
                ..sort(_newestFirst);
          if (records.isEmpty) {
            return const EmptyStateWidget(message: 'No submissions yet.');
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: records.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(
                  milliseconds: 280 + (index * 50).clamp(0, 350),
                ),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 18 * (1 - value)),
                      child: child,
                    ),
                  );
                },
                child: _RecordCard(record: records[index]),
              );
            },
          );
        },
      ),
    );
  }
}

int _newestFirst(DatasetRecordModel a, DatasetRecordModel b) {
  final aDate =
      a.createdAt ?? a.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bDate =
      b.createdAt ?? b.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  return bDate.compareTo(aDate);
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record});

  final DatasetRecordModel record;

  @override
  Widget build(BuildContext context) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              record.kitDisplayName,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(record.reviewStatus)),
                Chip(label: Text(record.selectedResult)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Selected Result: ${record.selectedResult}'),
            if (record.imageUrl.isNotEmpty) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  record.imageUrl,
                  height: 150,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
            ],
            const SizedBox(height: 4),
            Text('Kit Name: ${record.kitDisplayName}'),
            if (record.kitId.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('Kit ID: ${record.kitId}'),
            ],
            if (record.submittedAt != null) ...[
              const SizedBox(height: 4),
              Text('Submitted: ${record.submittedAtDigital}'),
            ],
          ],
        ),
      ),
    );
  }
}
