import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../models/dataset_record_model.dart';
import '../../services/database_service.dart';
import '../../services/export_file_deleter_stub.dart'
    if (dart.library.io) '../../services/export_file_deleter_io.dart';
import '../../services/export_history_store_stub.dart'
    if (dart.library.io) '../../services/export_history_store_io.dart';
import '../../services/export_service.dart';
import '../../widgets/entry_animation.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/loading_widget.dart';
import '../Registrations/login.dart';

class AddTestsWidget extends StatelessWidget {
  const AddTestsWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return const AdminDashboardPage();
  }
}

class AdminDashboardPage extends StatefulWidget {
  const AdminDashboardPage({super.key});

  @override
  State<AdminDashboardPage> createState() => _AdminDashboardPageState();
}

class _AdminDashboardPageState extends State<AdminDashboardPage> {
  final DatabaseService _databaseService = DatabaseService();
  final ExportService _exportService = ExportService();
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _adminScrollController = ScrollController();

  int _selectedPageIndex = 0;
  String _selectedRecordFilter = 'All';
  String _selectedExportFormat = 'xls';
  bool _isExporting = false;
  bool _isLoadingRecords = true;
  bool _isLoadingMoreRecords = false;
  bool _hasMoreRecords = true;
  String? _recordsError;
  int? _totalRecordCount;
  DateTimeRange? _selectedDateRange;
  DocumentSnapshot<Map<String, dynamic>>? _lastRecordDocument;
  final List<DatasetRecordModel> _loadedRecords = [];
  final List<_ExportHistoryItem> _recentExports = [];
  static const int _recordsPageSize = 25;

  static const _pages = [
    _AdminPage('Dashboard', 'Admin Dashboard', Icons.dashboard_rounded),
    _AdminPage('Kits', 'Data Entry', Icons.inventory_2_rounded),
    _AdminPage('Records', 'Scanned Reports', Icons.fact_check_outlined),
    _AdminPage('Export', 'Dataset Export', Icons.file_download_outlined),
    _AdminPage('Profile', 'Profile', Icons.settings_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _loadInitialRecords();
    _loadRecentExports();
  }

  @override
  void dispose() {
    _adminScrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialRecords() async {
    setState(() {
      _isLoadingRecords = true;
      _recordsError = null;
      _loadedRecords.clear();
      _lastRecordDocument = null;
      _hasMoreRecords = true;
    });

    try {
      final countFuture = _databaseService.countRecords();
      final pageFuture = _databaseService.fetchRecordsPage(
        limit: _recordsPageSize,
      );
      final results = await Future.wait<Object>([countFuture, pageFuture]);
      final totalCount = results[0] as int;
      final snapshot = results[1] as QuerySnapshot<Map<String, dynamic>>;

      if (!mounted) return;
      setState(() {
        _totalRecordCount = totalCount;
        _loadedRecords
          ..clear()
          ..addAll(snapshot.docs.map(DatasetRecordModel.fromFirestore));
        _lastRecordDocument = snapshot.docs.isEmpty ? null : snapshot.docs.last;
        _hasMoreRecords = snapshot.docs.length == _recordsPageSize;
        _lastLoadedRecords = List.of(_loadedRecords);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _recordsError = e.toString());
    } finally {
      if (mounted) setState(() => _isLoadingRecords = false);
    }
  }

  Future<void> _loadMoreRecords() async {
    if (_isLoadingMoreRecords || !_hasMoreRecords) return;

    setState(() {
      _isLoadingMoreRecords = true;
      _recordsError = null;
    });

    try {
      final snapshot = await _databaseService.fetchRecordsPage(
        limit: _recordsPageSize,
        startAfter: _lastRecordDocument,
      );

      if (!mounted) return;
      setState(() {
        _loadedRecords.addAll(
          snapshot.docs.map(DatasetRecordModel.fromFirestore),
        );
        _lastRecordDocument =
            snapshot.docs.isEmpty ? _lastRecordDocument : snapshot.docs.last;
        _hasMoreRecords = snapshot.docs.length == _recordsPageSize;
        _lastLoadedRecords = List.of(_loadedRecords);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _recordsError = e.toString());
    } finally {
      if (mounted) setState(() => _isLoadingMoreRecords = false);
    }
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange:
          _selectedDateRange ??
          DateTimeRange(start: now.subtract(const Duration(days: 6)), end: now),
    );
    if (picked == null || !mounted) return;

    setState(() => _selectedDateRange = picked);
  }

  void _clearDateRange() {
    if (_selectedDateRange == null) return;
    setState(() => _selectedDateRange = null);
  }

  Future<void> _export() async {
    setState(() => _isExporting = true);
    try {
      final exportRecords = _lastLoadedRecords;
      final path = await _exportService.exportRecords(
        _selectedExportFormat,
        records: exportRecords,
      );
      if (!mounted) return;
      final item = _ExportHistoryItem(
        path: path,
        format: _selectedExportFormat,
        recordCount: exportRecords.length,
        exportedAt: DateTime.now(),
      );
      setState(() {
        _recentExports.insert(0, item);
        if (_recentExports.length > 20) {
          _recentExports.removeRange(20, _recentExports.length);
        }
      });
      await _saveRecentExports();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Dataset exported to $path')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  void _selectPage(int index) {
    final shouldReloadRecords = _selectedRecordFilter != 'All';
    setState(() {
      _selectedPageIndex = index;
      _selectedRecordFilter = 'All';
      _searchController.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_adminScrollController.hasClients) return;
      _adminScrollController.jumpTo(0);
    });
    if (shouldReloadRecords) {
      _loadInitialRecords();
    }
  }

  Future<void> _searchRecords(String value) async {
    setState(() {});
    if (value.trim().isEmpty || !_hasMoreRecords || _isLoadingMoreRecords) {
      return;
    }
    await _loadMoreRecords();
  }

  List<DatasetRecordModel> _lastLoadedRecords = [];

  Future<void> _loadRecentExports() async {
    final exports = await loadExportHistoryMaps();
    if (!mounted) return;
    setState(() {
      _recentExports
        ..clear()
        ..addAll(exports.map(_ExportHistoryItem.fromMap));
    });
  }

  Future<void> _saveRecentExports() {
    return saveExportHistoryMaps(
      _recentExports.map((item) => item.toMap()).toList(),
    );
  }

  Future<void> _deleteRecentExport(_ExportHistoryItem item) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete export?'),
            content: Text(
              'Remove ${item.fileName} from recent exports and delete the saved file if available.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (shouldDelete != true) return;

    final deleted = await deleteExportFile(item.path);
    if (!mounted) return;
    setState(() => _recentExports.remove(item));
    await _saveRecentExports();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          deleted
              ? 'Export file deleted.'
              : 'Removed from recent exports. File deletion is not available here.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _AdminColors.page,
      bottomNavigationBar: _AdminBottomNav(
        pages: _pages,
        selectedIndex: _selectedPageIndex,
        onSelected: _selectPage,
      ),
      body:
          _isLoadingRecords
              ? const LoadingWidget()
              : _recordsError != null && _loadedRecords.isEmpty
              ? EmptyStateWidget(
                message: 'Could not load records: $_recordsError',
              )
              : LayoutBuilder(
                builder: (context, constraints) {
                  final records = List<DatasetRecordModel>.of(_loadedRecords)
                    ..sort(_newestFirst);
                  final filteredRecords = _filterRecords(records);
                  _lastLoadedRecords = filteredRecords;

                  return SafeArea(
                    child: _AdminSurface(
                      page: _pages[_selectedPageIndex],
                      pageIndex: _selectedPageIndex,
                      scrollController: _adminScrollController,
                      records: filteredRecords,
                      allRecords: records,
                      totalRecordCount: _totalRecordCount ?? records.length,
                      selectedDateRange: _selectedDateRange,
                      hasMoreRecords: _hasMoreRecords,
                      isLoadingMoreRecords: _isLoadingMoreRecords,
                      onLoadMoreRecords: _loadMoreRecords,
                      onDateRangePressed: _pickDateRange,
                      onClearDateRange: _clearDateRange,
                      selectedRecordFilter: _selectedRecordFilter,
                      selectedExportFormat: _selectedExportFormat,
                      isExporting: _isExporting,
                      searchController: _searchController,
                      onSearchChanged: _searchRecords,
                      onFilterChanged:
                          (filter) =>
                              setState(() => _selectedRecordFilter = filter),
                      onFormatChanged:
                          (format) =>
                              setState(() => _selectedExportFormat = format),
                      onExport: _export,
                      recentExports: _recentExports,
                      onDeleteRecentExport: _deleteRecentExport,
                      onPageSelected: _selectPage,
                      onBack: () {
                        if (_selectedPageIndex == 0) return;
                        _selectPage(0);
                      },
                      onLogout: _logout,
                    ),
                  );
                },
              ),
    );
  }

  Future<void> _logout() async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Logout?'),
            content: const Text('Are you sure you want to logout from admin?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Logout'),
                style: FilledButton.styleFrom(
                  backgroundColor: _AdminColors.red,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
    );
    if (shouldLogout != true || !mounted) return;
    Get.offAll(() => const Login(), transition: Transition.rightToLeft);
  }

  List<DatasetRecordModel> _filterRecords(List<DatasetRecordModel> records) {
    final query = _searchController.text.trim().toLowerCase();
    final page = _pages[_selectedPageIndex].name;

    return records.where((record) {
      final pageMatches = switch (page) {
        _ => true,
      };
      final filterMatches = switch (_selectedRecordFilter) {
        'Positive' => record.selectedResult == 'Positive',
        'Negative' => record.selectedResult == 'Negative',
        _ => true,
      };
      final recordDate = record.submittedAt ?? record.createdAt;
      final rangeMatches =
          _selectedDateRange == null ||
          (recordDate != null &&
              !recordDate.isBefore(_selectedDateRange!.start) &&
              !recordDate.isAfter(
                _dateRangeEndOfDay(_selectedDateRange!.end)!,
              ));
      final searchable =
          [
            record.recordId,
            record.userName,
            record.userEmail,
            record.testType,
            record.kitDisplayName,
            record.kitId,
            record.qrCodeValue,
            record.matchedQrCode,
            record.matchedKitName,
            record.kitCategory,
            record.kitSampleType,
            record.kitManufacturer,
            record.imageName,
            record.selectedResult,
          ].join(' ').toLowerCase();
      return pageMatches &&
          filterMatches &&
          rangeMatches &&
          (query.isEmpty || searchable.contains(query));
    }).toList();
  }
}

class _AdminSurface extends StatelessWidget {
  const _AdminSurface({
    required this.page,
    required this.pageIndex,
    required this.scrollController,
    required this.records,
    required this.allRecords,
    required this.totalRecordCount,
    required this.selectedDateRange,
    required this.hasMoreRecords,
    required this.isLoadingMoreRecords,
    required this.onLoadMoreRecords,
    required this.onDateRangePressed,
    required this.onClearDateRange,
    required this.selectedRecordFilter,
    required this.selectedExportFormat,
    required this.isExporting,
    required this.searchController,
    required this.onSearchChanged,
    required this.onFilterChanged,
    required this.onFormatChanged,
    required this.onExport,
    required this.recentExports,
    required this.onDeleteRecentExport,
    required this.onPageSelected,
    required this.onBack,
    required this.onLogout,
  });

  final _AdminPage page;
  final int pageIndex;
  final ScrollController scrollController;
  final List<DatasetRecordModel> records;
  final List<DatasetRecordModel> allRecords;
  final int totalRecordCount;
  final DateTimeRange? selectedDateRange;
  final bool hasMoreRecords;
  final bool isLoadingMoreRecords;
  final VoidCallback onLoadMoreRecords;
  final VoidCallback onDateRangePressed;
  final VoidCallback onClearDateRange;
  final String selectedRecordFilter;
  final String selectedExportFormat;
  final bool isExporting;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onFilterChanged;
  final ValueChanged<String> onFormatChanged;
  final VoidCallback onExport;
  final List<_ExportHistoryItem> recentExports;
  final ValueChanged<_ExportHistoryItem> onDeleteRecentExport;
  final ValueChanged<int> onPageSelected;
  final VoidCallback onBack;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TopBar(page: page, pageIndex: pageIndex, onBack: onBack),
        Expanded(
          child: _AnimatedAdminBackground(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontalPadding =
                    constraints.maxWidth <= 420
                        ? 10.0
                        : constraints.maxWidth < 520
                        ? 14.0
                        : 24.0;
                return ListView(
                  controller: scrollController,
                  key: ValueKey(pageIndex),
                  padding: EdgeInsets.fromLTRB(
                    horizontalPadding,
                    constraints.maxWidth <= 520 ? 14 : 22,
                    horizontalPadding,
                    34,
                  ),
                  children: [
                    switch (pageIndex) {
                      0 => _DashboardHome(
                        records: records,
                        onPageTap: onPageSelected,
                      ),
                      1 => const _QrKitsPage(),
                      2 => _AllRecordsPage(
                        records: records,
                        allRecords: allRecords,
                        totalRecordCount: totalRecordCount,
                        selectedDateRange: selectedDateRange,
                        hasMoreRecords: hasMoreRecords,
                        isLoadingMoreRecords: isLoadingMoreRecords,
                        onLoadMoreRecords: onLoadMoreRecords,
                        onDateRangePressed: onDateRangePressed,
                        onClearDateRange: onClearDateRange,
                        selectedFilter: selectedRecordFilter,
                        searchController: searchController,
                        onSearchChanged: onSearchChanged,
                        onFilterChanged: onFilterChanged,
                      ),
                      3 => _DatasetExportPage(
                        records: records,
                        allRecords: allRecords,
                        selectedFormat: selectedExportFormat,
                        isExporting: isExporting,
                        onFormatChanged: onFormatChanged,
                        onExport: onExport,
                        recentExports: recentExports,
                        onDeleteRecentExport: onDeleteRecentExport,
                      ),
                      _ => _AdminProfilePage(onLogout: onLogout),
                    },
                  ],
                );
              },
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimatedAdminBackground extends StatefulWidget {
  const _AnimatedAdminBackground({required this.child});

  final Widget child;

  @override
  State<_AnimatedAdminBackground> createState() =>
      _AnimatedAdminBackgroundState();
}

class _AnimatedAdminBackgroundState extends State<_AnimatedAdminBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 7),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final value = _controller.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment(-0.9 + value * 0.6, -1),
              end: Alignment(0.8 - value * 0.4, 1),
              colors: const [
                Color(0xFFF8FAFD),
                Color(0xFFEFF7FF),
                Color(0xFFF7FFFC),
              ],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _DashboardHome extends StatelessWidget {
  const _DashboardHome({required this.records, required this.onPageTap});

  final List<DatasetRecordModel> records;
  final ValueChanged<int>? onPageTap;

  @override
  Widget build(BuildContext context) {
    final stats = _RecordStats(records);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _MetricGrid(
          metrics: [
            _MetricData(
              'Total Records',
              stats.total,
              Icons.description_rounded,
              _AdminColors.blue,
            ),
            _MetricData(
              'Positive Cases',
              stats.positive,
              Icons.coronavirus_rounded,
              _AdminColors.green,
            ),
            _MetricData(
              'Negative Cases',
              stats.negative,
              Icons.health_and_safety_outlined,
              _AdminColors.red,
            ),
          ],
        ),
        const SizedBox(height: 18),
        _ResponsivePair(
          left: _WeeklyChart(records: records),
          right: _ResultDistribution(stats: stats),
        ),
        const SizedBox(height: 22),
        _RecentSubmissions(
          records: records.take(4).toList(),
          onViewAll: () => onPageTap?.call(2),
        ),
        const SizedBox(height: 22),
        _QuickActions(onTap: onPageTap),
      ],
    );
  }
}

class _AllRecordsPage extends StatelessWidget {
  const _AllRecordsPage({
    required this.records,
    required this.allRecords,
    required this.totalRecordCount,
    required this.selectedDateRange,
    required this.hasMoreRecords,
    required this.isLoadingMoreRecords,
    required this.onLoadMoreRecords,
    required this.onDateRangePressed,
    required this.onClearDateRange,
    required this.selectedFilter,
    required this.searchController,
    required this.onSearchChanged,
    required this.onFilterChanged,
  });

  final List<DatasetRecordModel> records;
  final List<DatasetRecordModel> allRecords;
  final int totalRecordCount;
  final DateTimeRange? selectedDateRange;
  final bool hasMoreRecords;
  final bool isLoadingMoreRecords;
  final VoidCallback onLoadMoreRecords;
  final VoidCallback onDateRangePressed;
  final VoidCallback onClearDateRange;
  final String selectedFilter;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<String> onFilterChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SummaryBanner(
          icon: Icons.apps_rounded,
          label: 'Total Records',
          value: totalRecordCount.toString(),
          color: _AdminColors.blue,
        ),
        const SizedBox(height: 22),
        _SearchAndFilterBar(
          controller: searchController,
          onChanged: onSearchChanged,
        ),
        const SizedBox(height: 14),
        _RecordFilterControls(
          selectedFilter: selectedFilter,
          onFilterChanged: onFilterChanged,
          selectedDateRange: selectedDateRange,
          onDateRangePressed: onDateRangePressed,
          onClearDateRange: onClearDateRange,
        ),
        const SizedBox(height: 20),
        if (records.isEmpty)
          const _EmptyPanel(message: 'No records match this filter.')
        else ...[
          ...records.map(_RecordCard.new),
          const SizedBox(height: 4),
          _PaginationFooter(
            loadedCount: allRecords.length,
            totalCount: totalRecordCount,
            hasMore: hasMoreRecords,
            isLoading: isLoadingMoreRecords,
            onLoadMore: onLoadMoreRecords,
          ),
        ],
      ],
    );
  }
}

class _PaginationFooter extends StatelessWidget {
  const _PaginationFooter({
    required this.loadedCount,
    required this.totalCount,
    required this.hasMore,
    required this.isLoading,
    required this.onLoadMore,
  });

  final int loadedCount;
  final int totalCount;
  final bool hasMore;
  final bool isLoading;
  final VoidCallback onLoadMore;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 520;
    final label =
        totalCount > 0
            ? 'Showing $loadedCount of $totalCount records'
            : 'Showing $loadedCount records';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          label,
          textAlign: compact ? TextAlign.center : TextAlign.left,
          style: const TextStyle(color: _AdminColors.muted),
        ),
        const SizedBox(height: 10),
        if (hasMore)
          OutlinedButton.icon(
            onPressed: isLoading ? null : onLoadMore,
            icon:
                isLoading
                    ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Icon(Icons.expand_more_rounded),
            label: Text(isLoading ? 'Loading more...' : 'Load more records'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          )
        else
          const Text(
            'All loaded records are visible.',
            textAlign: TextAlign.center,
            style: TextStyle(color: _AdminColors.muted),
          ),
      ],
    );
  }
}

class _DatasetExportPage extends StatelessWidget {
  const _DatasetExportPage({
    required this.records,
    required this.allRecords,
    required this.selectedFormat,
    required this.isExporting,
    required this.onFormatChanged,
    required this.onExport,
    required this.recentExports,
    required this.onDeleteRecentExport,
  });

  final List<DatasetRecordModel> records;
  final List<DatasetRecordModel> allRecords;
  final String selectedFormat;
  final bool isExporting;
  final ValueChanged<String> onFormatChanged;
  final VoidCallback onExport;
  final List<_ExportHistoryItem> recentExports;
  final ValueChanged<_ExportHistoryItem> onDeleteRecentExport;

  @override
  Widget build(BuildContext context) {
    final stats = _RecordStats(allRecords);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          title: 'Dataset Export',
          subtitle: 'Export rapid test records in your preferred format.',
        ),
        const SizedBox(height: 20),
        _MetricGrid(
          metrics: [
            _MetricData(
              'Total Records',
              stats.total,
              Icons.description_rounded,
              _AdminColors.blue,
            ),
            _MetricData(
              'Export Records',
              records.length,
              Icons.file_copy_outlined,
              _AdminColors.green,
            ),
            _MetricData(
              'Last Export',
              records.isEmpty ? 0 : records.length,
              Icons.event_rounded,
              _AdminColors.purple,
            ),
          ],
        ),
        const SizedBox(height: 22),
        _Panel(
          title: 'Export Format',
          subtitle: 'Choose your preferred file format.',
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _FormatButton(
                label: 'CSV',
                subtitle: 'Comma separated values',
                icon: Icons.table_rows_rounded,
                value: 'csv',
                selected: selectedFormat == 'csv',
                onTap: onFormatChanged,
              ),
              _FormatButton(
                label: 'Excel',
                subtitle: 'Microsoft Excel format',
                icon: Icons.dataset_rounded,
                value: 'xls',
                selected: selectedFormat == 'xls',
                onTap: onFormatChanged,
              ),
              _FormatButton(
                label: 'JSON',
                subtitle: 'JavaScript Object Notation',
                icon: Icons.data_object_rounded,
                value: 'json',
                selected: selectedFormat == 'json',
                onTap: onFormatChanged,
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        _ExportPreview(
          records: records.take(10).toList(),
          total: records.length,
        ),
        const SizedBox(height: 18),
        FilledButton.icon(
          onPressed: isExporting ? null : onExport,
          icon:
              isExporting
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.download_rounded),
          label: Text(
            'Export Dataset (${records.length} Records)',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(58),
            backgroundColor: _AdminColors.blue,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 22),
        _RecentExports(exports: recentExports, onDelete: onDeleteRecentExport),
      ],
    );
  }
}

class _AdminProfilePage extends StatelessWidget {
  const _AdminProfilePage({required this.onLogout});

  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Panel(
          title: 'Admin Profile',
          subtitle: 'Manage the current admin session.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 34,
                    backgroundColor: Color(0xFFE7F1FF),
                    child: Icon(
                      Icons.person_rounded,
                      color: _AdminColors.navy,
                      size: 34,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: const [
                        Text(
                          'Rapid Test Admin',
                          style: TextStyle(
                            color: _AdminColors.navy,
                            fontSize: 20,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 5),
                        Text(
                          'Administrator access',
                          style: TextStyle(color: _AdminColors.muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              FilledButton.icon(
                onPressed: onLogout,
                icon: const Icon(Icons.logout_rounded),
                label: const Text('Logout'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(54),
                  backgroundColor: _AdminColors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _QrKitsPage extends StatefulWidget {
  const _QrKitsPage();

  @override
  State<_QrKitsPage> createState() => _QrKitsPageState();
}

class _QrKitsPageState extends State<_QrKitsPage> {
  final DatabaseService _databaseService = DatabaseService();
  final TextEditingController _qrCodeController = TextEditingController();
  final TextEditingController _kitNameController = TextEditingController();
  final TextEditingController _categoryController = TextEditingController();
  final TextEditingController _sampleTypeController = TextEditingController();
  final TextEditingController _manufacturerController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final ImagePicker _imagePicker = ImagePicker();
  final MobileScannerController _qrImageScannerController =
      MobileScannerController(
        autoStart: false,
        formats: const [BarcodeFormat.qrCode],
      );
  String? _editingQrCode;
  Uint8List? _selectedQrImageBytes;
  String? _selectedQrImageName;
  String? _savedQrImageUrl;
  bool _isSaving = false;
  bool _isReadingQr = false;

  @override
  void initState() {
    super.initState();
    _seedDefaultsSilently();
  }

  @override
  void dispose() {
    _qrImageScannerController.dispose();
    _qrCodeController.dispose();
    _kitNameController.dispose();
    _categoryController.dispose();
    _sampleTypeController.dispose();
    _manufacturerController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _seedDefaultsSilently() async {
    try {
      await _databaseService.seedDefaultQrKits();
    } catch (_) {
      // The visible button reports errors if the admin wants to retry.
    }
  }

  Future<void> _saveKit() async {
    final qrCode = _qrCodeController.text.trim();
    final kitName = _kitNameController.text.trim();
    if (qrCode.isEmpty || kitName.isEmpty) {
      _showMessage('Enter both QR code and kit name.');
      return;
    }

    setState(() => _isSaving = true);
    try {
      await _databaseService.saveQrKit(
        qrCode: qrCode,
        kitName: kitName,
        category: _categoryController.text,
        sampleType: _sampleTypeController.text,
        manufacturer: _manufacturerController.text,
        description: _descriptionController.text,
        qrImageBytes: _selectedQrImageBytes,
        qrImageName: _selectedQrImageName,
      );
      final editingQrCode = _editingQrCode;
      if (editingQrCode != null &&
          DatabaseService.normalizeQrKitCode(editingQrCode) !=
              DatabaseService.normalizeQrKitCode(qrCode)) {
        await _databaseService.deleteQrKit(editingQrCode);
      }
      if (!mounted) return;
      _clearEditingForm();
      _showMessage(
        editingQrCode == null ? 'QR kit uploaded.' : 'QR kit updated.',
      );
    } catch (e) {
      if (mounted) _showMessage('Could not save QR kit: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickQrImage(ImageSource source) async {
    setState(() => _isReadingQr = true);
    try {
      final pickedFile = await _imagePicker.pickImage(
        source: source,
        imageQuality: 60,
        maxWidth: 900,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (pickedFile == null) return;

      final capture = await _qrImageScannerController.analyzeImage(
        pickedFile.path,
      );
      final qrValue = capture?.barcodes
          .map((barcode) => barcode.rawValue)
          .whereType<String>()
          .map((value) => value.trim())
          .firstWhere((value) => value.isNotEmpty, orElse: () => '');

      if (!mounted) return;
      if (qrValue == null || qrValue.isEmpty) {
        _showMessage('No QR code found in this photo.');
        return;
      }

      _qrCodeController.text = DatabaseService.normalizeQrKitCode(qrValue);
      _selectedQrImageBytes = await pickedFile.readAsBytes();
      _selectedQrImageName = pickedFile.name;
      _savedQrImageUrl = null;
      _showMessage('QR code filled from photo.');
    } on PlatformException {
      final message =
          source == ImageSource.camera
              ? 'Camera could not be opened. Please allow camera permission.'
              : 'Photo picker could not be opened. Please allow photo access.';
      if (mounted) _showMessage(message);
    } catch (e) {
      if (mounted) _showMessage('Could not read QR from photo: $e');
    } finally {
      if (mounted) setState(() => _isReadingQr = false);
    }
  }

  Future<void> _seedDefaults() async {
    setState(() => _isSaving = true);
    try {
      await _databaseService.seedDefaultQrKits();
      if (mounted) _showMessage('Default QR kits added.');
    } catch (e) {
      if (mounted) _showMessage('Could not add default kits: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _deleteKit(QrKitRecord kit) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Delete QR kit?'),
            content: Text(
              '${kit.qrCode} will no longer resolve to a kit name.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
    );
    if (shouldDelete != true) return;

    try {
      await _databaseService.deleteQrKit(kit.qrCode);
      if (mounted) _showMessage('QR kit deleted.');
    } catch (e) {
      if (mounted) _showMessage('Could not delete QR kit: $e');
    }
  }

  void _editKit(QrKitRecord kit) {
    setState(() => _editingQrCode = kit.qrCode);
    _qrCodeController.text = kit.qrCode;
    _kitNameController.text = kit.kitName;
    _categoryController.text = kit.category;
    _sampleTypeController.text = kit.sampleType;
    _manufacturerController.text = kit.manufacturer;
    _descriptionController.text = kit.description;
    _selectedQrImageBytes = null;
    _selectedQrImageName = kit.qrImageName;
    _savedQrImageUrl = kit.qrImageUrl;
  }

  void _clearEditingForm() {
    setState(() => _editingQrCode = null);
    _qrCodeController.clear();
    _kitNameController.clear();
    _categoryController.clear();
    _sampleTypeController.clear();
    _manufacturerController.clear();
    _descriptionController.clear();
    _selectedQrImageBytes = null;
    _selectedQrImageName = null;
    _savedQrImageUrl = null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = _editingQrCode != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _QrUploadInfo(),
        const SizedBox(height: 18),
        _QrUploadDropZone(
          isReading: _isReadingQr,
          imageName: _selectedQrImageName,
          imageUrl: _savedQrImageUrl,
          onChooseImage: () => _pickQrImage(ImageSource.gallery),
          onCamera: () => _pickQrImage(ImageSource.camera),
        ),
        const SizedBox(height: 26),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Kit Information',
                style: TextStyle(
                  color: _AdminColors.navy,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            if (isEditing)
              TextButton.icon(
                onPressed: _isSaving ? null : _clearEditingForm,
                icon: const Icon(Icons.close_rounded),
                label: const Text('Cancel edit'),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _QrLabeledField(
          label: 'Kit Name',
          required: true,
          controller: _kitNameController,
          hintText: 'Enter kit name',
          icon: Icons.assignment_outlined,
        ),
        const SizedBox(height: 16),
        _QrLabeledField(
          label: 'QR Code',
          required: true,
          controller: _qrCodeController,
          hintText: 'Enter QR code',
          icon: Icons.qr_code_2_rounded,
          textCapitalization: TextCapitalization.characters,
        ),
        const SizedBox(height: 16),
        _QrLabeledField(
          label: 'Test Category',
          controller: _categoryController,
          hintText: 'Example: Infectious disease',
          icon: Icons.category_outlined,
        ),
        const SizedBox(height: 16),
        _QrLabeledField(
          label: 'Sample Type',
          controller: _sampleTypeController,
          hintText: 'Example: Blood, nasal swab, urine',
          icon: Icons.science_outlined,
        ),
        const SizedBox(height: 16),
        _QrLabeledField(
          label: 'Manufacturer',
          controller: _manufacturerController,
          hintText: 'Enter manufacturer or supplier',
          icon: Icons.business_outlined,
        ),
        const SizedBox(height: 16),
        _QrLabeledField(
          label: 'Description',
          controller: _descriptionController,
          hintText: 'Enter description',
          icon: Icons.notes_rounded,
          maxLines: 3,
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _isSaving ? null : _saveKit,
          icon:
              _isSaving
                  ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                  : const Icon(Icons.cloud_upload_outlined),
          label: Text(
            _isSaving
                ? 'Saving...'
                : isEditing
                ? 'Update QR Kit'
                : 'Upload Kit',
          ),
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(58),
            backgroundColor: _AdminColors.blue,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: _isSaving ? null : _seedDefaults,
            icon: const Icon(Icons.playlist_add_check_rounded),
            label: const Text('Add default kits'),
          ),
        ),
        const SizedBox(height: 22),
        _Panel(
          title: 'Saved QR Kits',
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _databaseService.watchQrKits(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return _QrKitsError(error: snapshot.error.toString());
              }
              final kits =
                  (snapshot.data?.docs ?? [])
                      .map((doc) => QrKitRecord.fromMap(doc.id, doc.data()))
                      .whereType<QrKitRecord>()
                      .toList();
              if (kits.isEmpty) {
                return const _InlineEmpty(
                  message:
                      'No QR kits saved yet. Add the default kits to start.',
                );
              }
              return LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth =
                      constraints.maxWidth >= 760
                          ? (constraints.maxWidth - 14) / 2
                          : constraints.maxWidth;
                  return Wrap(
                    spacing: 14,
                    runSpacing: 14,
                    children: [
                      for (final kit in kits)
                        SizedBox(
                          width: cardWidth,
                          child: _QrKitRow(
                            kit: kit,
                            onEdit: _editKit,
                            onDelete: _deleteKit,
                          ),
                        ),
                    ],
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _QrKitRow extends StatelessWidget {
  const _QrKitRow({
    required this.kit,
    required this.onEdit,
    required this.onDelete,
  });

  final QrKitRecord kit;
  final ValueChanged<QrKitRecord> onEdit;
  final ValueChanged<QrKitRecord> onDelete;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 520;
    final preview = _QrKitPreview(kit: kit, size: compact ? 52 : 58);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          kit.kitName,
          style: const TextStyle(
            color: _AdminColors.navy,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        SelectableText(
          kit.qrCode,
          style: const TextStyle(color: _AdminColors.muted),
        ),
        if (kit.qrImageName.isNotEmpty || kit.qrImageUrl.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(
            'Image: ${kit.qrImageName.isNotEmpty ? kit.qrImageName : 'Saved'}',
            style: const TextStyle(color: _AdminColors.muted, fontSize: 13),
          ),
        ],
      ],
    );
    final actions = Wrap(
      spacing: 4,
      children: [
        IconButton(
          tooltip: 'Edit',
          onPressed: () => onEdit(kit),
          icon: const Icon(Icons.edit_rounded),
        ),
        IconButton(
          tooltip: 'Delete',
          onPressed: () => onDelete(kit),
          icon: const Icon(Icons.delete_outline_rounded),
          color: _AdminColors.red,
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _AdminColors.purple.withOpacity(0.045),
        border: Border.all(color: _AdminColors.purple.withOpacity(0.16)),
        borderRadius: BorderRadius.circular(8),
      ),
      child:
          compact
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      preview,
                      const SizedBox(width: 12),
                      Expanded(child: details),
                    ],
                  ),
                  const SizedBox(height: 10),
                  actions,
                ],
              )
              : Row(
                children: [
                  preview,
                  const SizedBox(width: 14),
                  Expanded(child: details),
                  actions,
                ],
              ),
    );
  }
}

class _QrKitPreview extends StatefulWidget {
  const _QrKitPreview({required this.kit, required this.size});

  final QrKitRecord kit;
  final double size;

  @override
  State<_QrKitPreview> createState() => _QrKitPreviewState();
}

class _QrKitPreviewState extends State<_QrKitPreview> {
  Future<String?>? _storageUrlFuture;
  bool _directUrlFailed = false;

  @override
  void initState() {
    super.initState();
    _prepareStorageUrl();
  }

  @override
  void didUpdateWidget(_QrKitPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.kit.qrCode != widget.kit.qrCode ||
        oldWidget.kit.qrImageUrl != widget.kit.qrImageUrl ||
        oldWidget.kit.qrImageStoragePath != widget.kit.qrImageStoragePath) {
      _directUrlFailed = false;
      _prepareStorageUrl();
    }
  }

  void _prepareStorageUrl() {
    final storagePath = widget.kit.qrImageStoragePath.trim();
    _storageUrlFuture =
        storagePath.isEmpty
            ? null
            : FirebaseStorage.instance.ref(storagePath).getDownloadURL();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: widget.size,
        height: widget.size,
        color: Colors.white,
        child: _buildImage(),
      ),
    );
  }

  Widget _buildImage() {
    final imageUrl = widget.kit.qrImageUrl.trim();
    if (imageUrl.isEmpty || _directUrlFailed) {
      return _buildStorageImage();
    }

    final dataUrlBytes = _imageBytesFromDataUrl(imageUrl);
    if (dataUrlBytes != null) {
      return Image.memory(
        dataUrlBytes,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      );
    }

    return Image.network(
      imageUrl,
      width: widget.size,
      height: widget.size,
      fit: BoxFit.cover,
      errorBuilder: (_, __, ___) {
        if (_storageUrlFuture != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _directUrlFailed = true);
          });
        }
        return _buildStorageImage();
      },
    );
  }

  Widget _buildStorageImage() {
    final storageUrlFuture = _storageUrlFuture;
    if (storageUrlFuture == null) return _fallbackIcon(Icons.qr_code_2_rounded);

    return FutureBuilder<String?>(
      future: storageUrlFuture,
      builder: (context, snapshot) {
        final storageUrl = snapshot.data;
        if (storageUrl == null || storageUrl.isEmpty) {
          return _fallbackIcon(Icons.qr_code_2_rounded);
        }

        return Image.network(
          storageUrl,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          errorBuilder:
              (_, __, ___) => _fallbackIcon(Icons.broken_image_outlined),
        );
      },
    );
  }

  Widget _fallbackIcon(IconData icon) {
    return _SoftIcon(icon: icon, color: _AdminColors.purple, size: widget.size);
  }
}

class _MiniInfoChip extends StatelessWidget {
  const _MiniInfoChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.72),
        border: Border.all(color: _AdminColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: _AdminColors.muted),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: _AdminColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _QrUploadInfo extends StatelessWidget {
  const _QrUploadInfo();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _AdminColors.red.withOpacity(0.055),
        border: Border.all(color: _AdminColors.red.withOpacity(0.28)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 14,
            backgroundColor: _AdminColors.red,
            child: Icon(Icons.info_rounded, color: Colors.white, size: 17),
          ),
          SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Admin Data Entry',
                  style: TextStyle(
                    color: _AdminColors.navy,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Insert or update test-kit details from the admin panel. The saved QR code and kit information are used when users scan and submit results.',
                  style: TextStyle(
                    color: _AdminColors.muted,
                    fontSize: 13,
                    height: 1.25,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'QR/kit images are saved in Firebase Storage.',
                  style: TextStyle(
                    color: _AdminColors.red,
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    height: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QrUploadDropZone extends StatelessWidget {
  const _QrUploadDropZone({
    required this.isReading,
    required this.imageName,
    required this.imageUrl,
    required this.onChooseImage,
    required this.onCamera,
  });

  final bool isReading;
  final String? imageName;
  final String? imageUrl;
  final VoidCallback onChooseImage;
  final VoidCallback onCamera;

  @override
  Widget build(BuildContext context) {
    final hasImage =
        (imageName != null && imageName!.trim().isNotEmpty) ||
        (imageUrl != null && imageUrl!.trim().isNotEmpty);
    return CustomPaint(
      painter: _DashedBorderPainter(
        color: _AdminColors.blue.withOpacity(0.48),
        radius: 8,
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 30),
        child: Column(
          children: [
            CircleAvatar(
              radius: 46,
              backgroundColor: _AdminColors.blue.withOpacity(0.1),
              child: Icon(
                isReading
                    ? Icons.manage_search_rounded
                    : Icons.cloud_upload_outlined,
                color: _AdminColors.blue,
                size: 38,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              isReading
                  ? 'Reading QR Code Image'
                  : hasImage
                  ? 'QR Code Image Ready'
                  : 'Upload QR Code Image',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _AdminColors.navy,
                fontSize: 20,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasImage
                  ? (imageName ?? 'Saved QR image')
                  : 'JPG, PNG, WEBP, or GIF image.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _AdminColors.muted, fontSize: 16),
            ),
            const SizedBox(height: 22),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                FilledButton.icon(
                  onPressed: isReading ? null : onChooseImage,
                  icon: const Icon(Icons.image_outlined),
                  label: const Text('Choose Image'),
                  style: FilledButton.styleFrom(
                    backgroundColor: _AdminColors.blue,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(188, 54),
                    textStyle: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w900,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: isReading ? null : onCamera,
                  icon: const Icon(Icons.photo_camera_rounded),
                  label: const Text('Camera'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _AdminColors.navy,
                    minimumSize: const Size(128, 54),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QrLabeledField extends StatelessWidget {
  const _QrLabeledField({
    required this.label,
    required this.controller,
    required this.hintText,
    required this.icon,
    this.required = false,
    this.textCapitalization = TextCapitalization.none,
    this.maxLines = 1,
  });

  final String label;
  final bool required;
  final TextEditingController controller;
  final String hintText;
  final IconData icon;
  final TextCapitalization textCapitalization;
  final int maxLines;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _QrFieldLabel(label: label, required: required),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          textCapitalization: textCapitalization,
          maxLines: maxLines,
          decoration: _qrInputDecoration(hintText: hintText, icon: icon),
        ),
      ],
    );
  }
}

class _QrFieldLabel extends StatelessWidget {
  const _QrFieldLabel({required this.label, this.required = false});

  final String label;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        text: label,
        style: const TextStyle(color: _AdminColors.navy, fontSize: 15),
        children: [
          if (required)
            const TextSpan(
              text: ' *',
              style: TextStyle(color: _AdminColors.red),
            ),
        ],
      ),
    );
  }
}

InputDecoration _qrInputDecoration({
  required String hintText,
  required IconData icon,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(8),
    borderSide: const BorderSide(color: Color(0xFFD5DAE4)),
  );
  return InputDecoration(
    hintText: hintText,
    suffixIcon: Icon(icon, color: const Color(0xFF818A9C)),
    filled: true,
    fillColor: Colors.white,
    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
    border: border,
    enabledBorder: border,
    disabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: const BorderSide(color: _AdminColors.blue, width: 1.5),
    ),
  );
}

class _DashedBorderPainter extends CustomPainter {
  _DashedBorderPainter({required this.color, required this.radius});

  final Color color;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint =
        Paint()
          ..color = color
          ..strokeWidth = 1.4
          ..style = PaintingStyle.stroke;
    final rect = RRect.fromRectAndRadius(
      Offset.zero & size,
      Radius.circular(radius),
    );
    final path = Path()..addRRect(rect);
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        final next = math.min(distance + 8, metric.length);
        canvas.drawPath(metric.extractPath(distance, next), paint);
        distance += 14;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedBorderPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.radius != radius;
  }
}

class _QrKitsError extends StatelessWidget {
  const _QrKitsError({required this.error});

  final String error;

  @override
  Widget build(BuildContext context) {
    final isPermissionError = error.toLowerCase().contains('permission');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color:
            isPermissionError
                ? _AdminColors.red.withOpacity(0.06)
                : _AdminColors.orange.withOpacity(0.06),
        border: Border.all(
          color:
              isPermissionError
                  ? _AdminColors.red.withOpacity(0.18)
                  : _AdminColors.orange.withOpacity(0.18),
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isPermissionError
                ? Icons.lock_outline_rounded
                : Icons.error_outline_rounded,
            color: isPermissionError ? _AdminColors.red : _AdminColors.orange,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              isPermissionError
                  ? 'Firestore blocked QR kits. Deploy the updated firestore.rules, then reopen this page.'
                  : 'Could not load QR kits: $error',
              style: const TextStyle(color: _AdminColors.navy, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.page,
    required this.pageIndex,
    required this.onBack,
  });

  final _AdminPage page;
  final int pageIndex;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 520;
    return Container(
      height: compact ? 86 : 104,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 22),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF071B45), Color(0xFF0A2F66)],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            onPressed: pageIndex == 0 ? null : onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 28),
            color:
                pageIndex == 0 ? Colors.white.withOpacity(0.45) : Colors.white,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              page.title,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: true,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 22 : 26,
                fontWeight: FontWeight.w900,
                letterSpacing: 0,
              ),
            ),
          ),
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _AdminBottomNav extends StatelessWidget {
  const _AdminBottomNav({
    required this.pages,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_AdminPage> pages;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.72),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withOpacity(0.58)),
              boxShadow: [
                BoxShadow(
                  color: _AdminColors.navy.withOpacity(0.14),
                  blurRadius: 28,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: SizedBox(
              height: 72,
              child: Row(
                children: [
                  for (final entry in pages.indexed)
                    Expanded(
                      child: _AdminBottomNavItem(
                        page: entry.$2,
                        selected: entry.$1 == selectedIndex,
                        onTap: () => onSelected(entry.$1),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminBottomNavItem extends StatelessWidget {
  const _AdminBottomNavItem({
    required this.page,
    required this.selected,
    required this.onTap,
  });

  final _AdminPage page;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? _AdminColors.blue : const Color(0xFF606A80);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox.expand(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                width: 34,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient:
                      selected
                          ? const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF1E90FF), Color(0xFF8D5CF6)],
                          )
                          : null,
                  color: selected ? null : Colors.transparent,
                  borderRadius: BorderRadius.circular(11),
                  boxShadow:
                      selected
                          ? [
                            BoxShadow(
                              color: _AdminColors.blue.withOpacity(0.22),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ]
                          : null,
                ),
                child: AnimatedScale(
                  scale: selected ? 1.0 : 0.92,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  child: Icon(
                    page.icon,
                    color: selected ? Colors.white : color,
                    size: 23,
                  ),
                ),
              ),
              const SizedBox(height: 3),
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                ),
                child: Text(
                  page.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 520;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            color: _AdminColors.navy,
            fontSize: compact ? 22 : 25,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 6),
        Text(subtitle, style: const TextStyle(color: _AdminColors.muted)),
      ],
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.metrics});

  final List<_MetricData> metrics;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns =
            width >= 900
                ? 3
                : width >= 620
                ? 2
                : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: metrics.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: width <= 520 ? 126 : 142,
            crossAxisSpacing: width <= 520 ? 12 : 18,
            mainAxisSpacing: width <= 520 ? 12 : 18,
          ),
          itemBuilder: (context, index) => _MetricCard(data: metrics[index]),
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.data});

  final _MetricData data;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 520;
    return _Card(
      child: Row(
        children: [
          _SoftIcon(
            icon: data.icon,
            color: data.color,
            size: compact ? 48 : 58,
          ),
          SizedBox(width: compact ? 12 : 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _AdminColors.navy,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: compact ? 4 : 8),
                Text(
                  _formatCount(data.value),
                  style: TextStyle(
                    color: _AdminColors.navy,
                    fontSize: compact ? 26 : 30,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                SizedBox(height: compact ? 4 : 8),
                const Text(
                  '+12.5% vs previous 7 days',
                  style: TextStyle(color: _AdminColors.green, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponsivePair extends StatelessWidget {
  const _ResponsivePair({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 760) {
          return Column(children: [left, const SizedBox(height: 18), right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            const SizedBox(width: 18),
            Expanded(child: right),
          ],
        );
      },
    );
  }
}

class _WeeklyChart extends StatefulWidget {
  const _WeeklyChart({required this.records});

  final List<DatasetRecordModel> records;

  @override
  State<_WeeklyChart> createState() => _WeeklyChartState();
}

class _WeeklyChartState extends State<_WeeklyChart> {
  int _selectedDays = 7;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Weekly Submissions',
      trailing: PopupMenuButton<int>(
        initialValue: _selectedDays,
        tooltip: 'Select date range',
        onSelected: (value) => setState(() => _selectedDays = value),
        itemBuilder:
            (context) => const [
              PopupMenuItem(value: 7, child: Text('7 Days')),
              PopupMenuItem(value: 14, child: Text('14 Days')),
              PopupMenuItem(value: 30, child: Text('30 Days')),
            ],
        child: _MiniSelect(label: '$_selectedDays Days'),
      ),
      child: SizedBox(
        height: 230,
        child: CustomPaint(
          painter: _LineChartPainter(
            _weeklyCounts(widget.records, _selectedDays),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}

class _ResultDistribution extends StatelessWidget {
  const _ResultDistribution({required this.stats});

  final _RecordStats stats;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 520;
    return _Panel(
      title: 'Result Distribution',
      child: SizedBox(
        height: compact ? 270 : 230,
        child:
            compact
                ? Column(
                  children: [
                    Expanded(child: _DonutSummary(stats: stats)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 16,
                      runSpacing: 8,
                      alignment: WrapAlignment.center,
                      children: _resultLegend(stats),
                    ),
                  ],
                )
                : Row(
                  children: [
                    Expanded(child: _DonutSummary(stats: stats)),
                    const SizedBox(width: 14),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _resultLegend(stats, vertical: true),
                    ),
                  ],
                ),
      ),
    );
  }

  List<Widget> _resultLegend(_RecordStats stats, {bool vertical = false}) {
    final items = [
      _LegendDot(
        label:
            'Negative\n${stats.negative} (${_percent(stats.negative, stats.total)})',
        color: _AdminColors.teal,
      ),
      _LegendDot(
        label:
            'Positive\n${stats.positive} (${_percent(stats.positive, stats.total)})',
        color: _AdminColors.red,
      ),
    ];
    if (!vertical) return items;
    return [items.first, const SizedBox(height: 18), items.last];
  }
}

class _DonutSummary extends StatelessWidget {
  const _DonutSummary({required this.stats});

  final _RecordStats stats;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _DonutPainter(
        negative: stats.negative,
        positive: stats.positive,
      ),
      child: Center(
        child: Text(
          '${_formatCount(stats.total)}\nTotal',
          textAlign: TextAlign.center,
          style: const TextStyle(
            color: _AdminColors.navy,
            fontWeight: FontWeight.w900,
            height: 1.25,
          ),
        ),
      ),
    );
  }
}

class _RecentSubmissions extends StatelessWidget {
  const _RecentSubmissions({required this.records, required this.onViewAll});

  final List<DatasetRecordModel> records;
  final VoidCallback onViewAll;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Recent Submissions',
      trailing: TextButton(onPressed: onViewAll, child: const Text('View All')),
      child:
          records.isEmpty
              ? const _InlineEmpty(message: 'No submissions yet.')
              : Column(
                children: [
                  for (final record in records) ...[
                    _RecentSubmissionBox(record),
                    if (record != records.last) const SizedBox(height: 8),
                  ],
                ],
              ),
    );
  }
}

class _RecentSubmissionBox extends StatelessWidget {
  const _RecentSubmissionBox(this.record);

  final DatasetRecordModel record;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 520;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFD),
        border: Border.all(color: _AdminColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child:
          compact
              ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _PersonAvatar(name: record.userName, radius: 20),
                      const SizedBox(width: 10),
                      Expanded(child: _RecentSubmissionText(record: record)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _dateTime(record),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _AdminColors.muted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _CompactResultPill(result: record.selectedResult),
                    ],
                  ),
                ],
              )
              : Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _PersonAvatar(name: record.userName, radius: 22),
                  const SizedBox(width: 10),
                  Expanded(child: _RecentSubmissionText(record: record)),
                  Expanded(
                    child: Text(
                      _dateTime(record),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _AdminColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  _CompactResultPill(result: record.selectedResult),
                ],
              ),
    );
  }
}

class _RecentSubmissionText extends StatelessWidget {
  const _RecentSubmissionText({required this.record});

  final DatasetRecordModel record;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _displayName(record),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _AdminColors.navy,
            fontSize: 15,
            fontWeight: FontWeight.w900,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'ID: ${_shortId(record)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _AdminColors.muted,
            fontSize: 12,
            height: 1.2,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          _testName(record),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: _AdminColors.muted,
            fontSize: 12,
            height: 1.2,
          ),
        ),
      ],
    );
  }
}

class _CompactResultPill extends StatelessWidget {
  const _CompactResultPill({required this.result});

  final String result;

  @override
  Widget build(BuildContext context) {
    final color = switch (result) {
      'Positive' => _AdminColors.green,
      'Negative' => _AdminColors.red,
      'Clear' => _AdminColors.blue,
      _ => _AdminColors.orange,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.09),
        border: Border.all(color: color.withOpacity(0.22)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        result.isEmpty ? 'Pending' : result,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({required this.onTap});

  final ValueChanged<int>? onTap;

  @override
  Widget build(BuildContext context) {
    final actions = [
      _ActionTile(
        title: 'Kits',
        subtitle: 'Upload QR kits',
        icon: Icons.inventory_2_rounded,
        color: _AdminColors.blue,
        onTap: () => onTap?.call(1),
      ),
      _ActionTile(
        title: 'Records',
        subtitle: 'View all test records',
        icon: Icons.fact_check_outlined,
        color: _AdminColors.green,
        onTap: () => onTap?.call(2),
      ),
      _ActionTile(
        title: 'Export',
        subtitle: 'Download data',
        icon: Icons.file_download_outlined,
        color: _AdminColors.purple,
        onTap: () => onTap?.call(3),
      ),
    ];
    return _Panel(
      title: 'Quick Actions',
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth <= 560) {
            return Column(
              children: [
                for (final action in actions) ...[
                  SizedBox(width: double.infinity, child: action),
                  if (action != actions.last) const SizedBox(height: 12),
                ],
              ],
            );
          }
          return Wrap(spacing: 18, runSpacing: 14, children: actions);
        },
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = MediaQuery.sizeOf(context).width <= 520;
        final width =
            compact
                ? constraints.maxWidth
                : math.min(260.0, constraints.maxWidth);
        return SizedBox(
          width: width,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: EdgeInsets.all(compact ? 12 : 14),
              decoration: BoxDecoration(
                color: color.withOpacity(0.06),
                border: Border.all(color: color.withOpacity(0.2)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _SoftIcon(icon: icon, color: color, size: compact ? 42 : 48),
                  SizedBox(width: compact ? 10 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: TextStyle(
                            color: color,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: compact ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _AdminColors.muted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right_rounded, color: color),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard(this.record);

  final DatasetRecordModel record;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 520;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: _Card(
        child:
            compact
                ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _RecordThumbnail(record: record, size: 54),
                        const SizedBox(width: 12),
                        Expanded(child: _RecordIdentity(record: record)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          child: Text(
                            _dateTime(record),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: _AdminColors.muted,
                              height: 1.35,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _ResultPill(result: record.selectedResult),
                      ],
                    ),
                  ],
                )
                : Row(
                  children: [
                    _RecordThumbnail(record: record, size: 72),
                    const SizedBox(width: 18),
                    Expanded(flex: 3, child: _RecordIdentity(record: record)),
                    Expanded(
                      flex: 2,
                      child: Text(
                        _dateTime(record),
                        style: const TextStyle(
                          color: _AdminColors.muted,
                          height: 1.35,
                        ),
                      ),
                    ),
                    Wrap(
                      direction: Axis.vertical,
                      spacing: 8,
                      children: [_ResultPill(result: record.selectedResult)],
                    ),
                    const SizedBox(width: 10),
                    const Icon(
                      Icons.chevron_right_rounded,
                      color: _AdminColors.muted,
                    ),
                  ],
                ),
      ),
    );
  }
}

class _RecordIdentity extends StatelessWidget {
  const _RecordIdentity({required this.record});

  final DatasetRecordModel record;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 620;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          _displayName(record),
          maxLines: compact ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: _AdminColors.navy,
            fontSize: compact ? 18 : 21,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 5),
        Text(
          'ID: ${_shortId(record)}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _AdminColors.muted),
        ),
        const SizedBox(height: 8),
        Text(
          _testName(record),
          maxLines: compact ? 3 : 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: _AdminColors.muted),
        ),
        if (record.kitCategory.isNotEmpty ||
            record.kitSampleType.isNotEmpty ||
            record.kitManufacturer.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (record.kitCategory.isNotEmpty)
                _MiniInfoChip(label: record.kitCategory, icon: Icons.category),
              if (record.kitSampleType.isNotEmpty)
                _MiniInfoChip(label: record.kitSampleType, icon: Icons.science),
              if (record.kitManufacturer.isNotEmpty)
                _MiniInfoChip(
                  label: record.kitManufacturer,
                  icon: Icons.business,
                ),
            ],
          ),
        ],
      ],
    );
  }
}

class _RecordThumbnail extends StatefulWidget {
  const _RecordThumbnail({required this.record, required this.size});

  final DatasetRecordModel record;
  final double size;

  @override
  State<_RecordThumbnail> createState() => _RecordThumbnailState();
}

class _RecordThumbnailState extends State<_RecordThumbnail> {
  Future<String?>? _storageUrlFuture;
  bool _directUrlFailed = false;

  @override
  void initState() {
    super.initState();
    _prepareStorageUrl();
  }

  @override
  void didUpdateWidget(_RecordThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.record.recordId != widget.record.recordId ||
        oldWidget.record.imageStoragePath != widget.record.imageStoragePath) {
      _directUrlFailed = false;
      _prepareStorageUrl();
    }
  }

  void _prepareStorageUrl() {
    final storagePath = widget.record.imageStoragePath.trim();
    _storageUrlFuture =
        storagePath.isEmpty
            ? null
            : FirebaseStorage.instance.ref(storagePath).getDownloadURL();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.record.userName;
    final seed = name.codeUnits.fold<int>(0, (total, code) => total + code);
    final colors = [
      _AdminColors.blue,
      _AdminColors.green,
      _AdminColors.orange,
      _AdminColors.purple,
      _AdminColors.teal,
    ];
    final color = colors[seed % colors.length];
    final imageUrl = widget.record.imageUrl.trim();

    return SizedBox.square(
      dimension: widget.size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: _buildImage(imageUrl, name, color),
      ),
    );
  }

  Widget _buildImage(String imageUrl, String name, Color color) {
    if (imageUrl.isNotEmpty && !_directUrlFailed) {
      final dataUrlBytes = _imageBytesFromDataUrl(imageUrl);
      if (dataUrlBytes != null) {
        return Image.memory(
          dataUrlBytes,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        );
      }
      return Image.network(
        imageUrl,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          if (_storageUrlFuture != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _directUrlFailed = true);
            });
          }
          return _buildStorageImage(name, color);
        },
      );
    }

    return _buildStorageImage(name, color);
  }

  Widget _buildStorageImage(String name, Color color) {
    final storageUrlFuture = _storageUrlFuture;
    if (storageUrlFuture == null) {
      return _ThumbnailInitial(name: name, color: color);
    }

    return FutureBuilder<String?>(
      future: storageUrlFuture,
      builder: (context, snapshot) {
        final storageUrl = snapshot.data;
        if (storageUrl == null || storageUrl.isEmpty) {
          return _ThumbnailInitial(name: name, color: color);
        }

        return Image.network(
          storageUrl,
          width: widget.size,
          height: widget.size,
          fit: BoxFit.cover,
          errorBuilder:
              (_, __, ___) => _ThumbnailInitial(name: name, color: color),
        );
      },
    );
  }
}

Uint8List? _imageBytesFromDataUrl(String value) {
  final commaIndex = value.indexOf(',');
  if (!value.startsWith('data:image/') || commaIndex < 0) return null;
  try {
    return base64Decode(value.substring(commaIndex + 1));
  } catch (_) {
    return null;
  }
}

class _ThumbnailInitial extends StatelessWidget {
  const _ThumbnailInitial({required this.name, required this.color});

  final String name;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      alignment: Alignment.center,
      color: color.withOpacity(0.13),
      child: Icon(Icons.image_outlined, color: color, size: 22),
    );
  }
}

class _ExportPreview extends StatelessWidget {
  const _ExportPreview({required this.records, required this.total});

  final List<DatasetRecordModel> records;
  final int total;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 520;
    final shownCount = records.length;
    return _Panel(
      title: 'Preview (first $shownCount results)',
      trailing: Text(
        '$total results matched with your filter',
        style: const TextStyle(color: _AdminColors.blue),
      ),
      child:
          records.isEmpty
              ? const _InlineEmpty(message: 'No records to export.')
              : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: DataTable(
                  headingRowHeight: 42,
                  dataRowMinHeight: 44,
                  dataRowMaxHeight: 50,
                  columnSpacing: compact ? 18 : 30,
                  columns: const [
                    DataColumn(label: Text('Record ID')),
                    DataColumn(label: Text('Test Type')),
                    DataColumn(label: Text('Kit Name')),
                    DataColumn(label: Text('User Result')),
                    DataColumn(label: Text('Date')),
                  ],
                  rows:
                      records
                          .map(
                            (record) => DataRow(
                              cells: [
                                DataCell(Text(_shortId(record))),
                                DataCell(Text(_testName(record))),
                                DataCell(Text(record.kitDisplayName)),
                                DataCell(
                                  _ResultPill(result: record.selectedResult),
                                ),
                                DataCell(Text(_dateTime(record))),
                              ],
                            ),
                          )
                          .toList(),
                ),
              ),
    );
  }
}

class _RecentExports extends StatelessWidget {
  const _RecentExports({required this.exports, required this.onDelete});

  final List<_ExportHistoryItem> exports;
  final ValueChanged<_ExportHistoryItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 520;
    return _Panel(
      title: 'Recent Exports',
      trailing: TextButton(
        onPressed: exports.isEmpty ? null : () => _showAllExports(context),
        child: const Text('View All'),
      ),
      child:
          exports.isEmpty
              ? const _InlineEmpty(message: 'No exports downloaded yet.')
              : Column(
                children: [
                  for (final item in exports.take(3)) ...[
                    _RecentExportTile(
                      item: item,
                      compact: compact,
                      onDelete: () => onDelete(item),
                    ),
                    if (item != exports.take(3).last) const Divider(height: 18),
                  ],
                ],
              ),
    );
  }

  void _showAllExports(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder:
          (context) => SafeArea(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 24),
              children: [
                const Text(
                  'All Exports',
                  style: TextStyle(
                    color: _AdminColors.navy,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                for (final item in exports)
                  _RecentExportTile(
                    item: item,
                    compact: true,
                    onDelete: () {
                      Navigator.pop(context);
                      onDelete(item);
                    },
                  ),
              ],
            ),
          ),
    );
  }
}

class _RecentExportTile extends StatelessWidget {
  const _RecentExportTile({
    required this.item,
    required this.compact,
    required this.onDelete,
  });

  final _ExportHistoryItem item;
  final bool compact;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: _SoftIcon(
        icon: Icons.insert_drive_file_rounded,
        color: _AdminColors.green,
        size: compact ? 40 : 46,
      ),
      title: Text(item.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        '${item.recordCount} records  -  ${_dateTimeLabel(item.exportedAt)}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: IconButton(
        tooltip: 'Delete export',
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline_rounded, color: _AdminColors.red),
      ),
    );
  }
}

class _ExportHistoryItem {
  const _ExportHistoryItem({
    required this.path,
    required this.format,
    required this.recordCount,
    required this.exportedAt,
  });

  factory _ExportHistoryItem.fromMap(Map<String, dynamic> data) {
    return _ExportHistoryItem(
      path: data['path']?.toString() ?? '',
      format: data['format']?.toString() ?? 'csv',
      recordCount: int.tryParse(data['recordCount']?.toString() ?? '') ?? 0,
      exportedAt:
          DateTime.tryParse(data['exportedAt']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final String path;
  final String format;
  final int recordCount;
  final DateTime exportedAt;

  Map<String, dynamic> toMap() {
    return {
      'path': path,
      'format': format,
      'recordCount': recordCount,
      'exportedAt': exportedAt.toIso8601String(),
    };
  }

  String get fileName {
    final normalized = path.replaceAll('\\', '/');
    final name = normalized.split('/').last;
    if (name.startsWith('Downloaded: ')) {
      return name.replaceFirst('Downloaded: ', '');
    }
    if (name.isNotEmpty && !name.startsWith('Downloaded:')) return name;
    return 'dataset_records_${exportedAt.millisecondsSinceEpoch}.$format';
  }
}

String _dateTimeLabel(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')} '
      '${date.hour.toString().padLeft(2, '0')}:'
      '${date.minute.toString().padLeft(2, '0')}';
}

DateTime? _dateRangeEndOfDay(DateTime? date) {
  if (date == null) return null;
  return DateTime(date.year, date.month, date.day, 23, 59, 59, 999);
}

String _dateRangeLabel(DateTimeRange? range) {
  if (range == null) return 'All dates';
  return '${_shortDateLabel(range.start)} - ${_shortDateLabel(range.end)}';
}

String _shortDateLabel(DateTime date) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${months[date.month - 1]} ${date.day}, ${date.year}';
}

class _SearchAndFilterBar extends StatelessWidget {
  const _SearchAndFilterBar({
    required this.controller,
    required this.onChanged,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth <= 520;
        final searchField = TextField(
          controller: controller,
          onChanged: onChanged,
          decoration: InputDecoration(
            hintText:
                compact
                    ? 'Search records...'
                    : 'Search by name, ID or test type...',
            prefixIcon: const Icon(Icons.search_rounded, size: 21),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 42,
              minHeight: 48,
            ),
            contentPadding: EdgeInsets.symmetric(
              horizontal: compact ? 10 : 14,
              vertical: 15,
            ),
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _AdminColors.border),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: _AdminColors.border),
            ),
          ),
        );
        if (compact) {
          return searchField;
        }

        final filterButton = OutlinedButton.icon(
          onPressed: () {},
          icon: const Icon(Icons.filter_alt_outlined),
          label: const Text('Filters'),
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(54),
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        );

        return Row(
          children: [
            Expanded(child: searchField),
            const SizedBox(width: 16),
            SizedBox(width: 128, child: filterButton),
          ],
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({
    required this.title,
    required this.child,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 520;
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (compact)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _PanelTitle(title: title, subtitle: subtitle),
                if (trailing != null) ...[const SizedBox(height: 8), trailing!],
              ],
            )
          else
            Row(
              children: [
                Expanded(child: _PanelTitle(title: title, subtitle: subtitle)),
                if (trailing != null) trailing!,
              ],
            ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }
}

class _PanelTitle extends StatelessWidget {
  const _PanelTitle({required this.title, required this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: _AdminColors.navy,
            fontSize: 18,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 5),
          Text(subtitle!, style: const TextStyle(color: _AdminColors.muted)),
        ],
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final effectivePadding =
        MediaQuery.sizeOf(context).width <= 520
            ? const EdgeInsets.all(14)
            : const EdgeInsets.all(20);
    return EntryAnimation(
      child: Container(
        width: double.infinity,
        padding: effectivePadding,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: _AdminColors.border),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _SummaryBanner extends StatelessWidget {
  const _SummaryBanner({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth <= 520;
        return _Card(
          child:
              compact
                  ? Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      _SoftIcon(icon: icon, color: color, size: 52),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _SummaryValue(
                          label: label,
                          value: value,
                          compact: true,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const _SummaryTrend(compact: true),
                    ],
                  )
                  : Row(
                    children: [
                      _SoftIcon(icon: icon, color: color, size: 72),
                      const SizedBox(width: 22),
                      Expanded(
                        child: _SummaryValue(
                          label: label,
                          value: value,
                          compact: false,
                        ),
                      ),
                      const _SummaryTrend(compact: false),
                    ],
                  ),
        );
      },
    );
  }
}

class _SummaryTrend extends StatelessWidget {
  const _SummaryTrend({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: compact ? 118 : null,
      child: Row(
        mainAxisSize: compact ? MainAxisSize.max : MainAxisSize.min,
        children: [
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '+12.5%',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _AdminColors.green,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'vs previous 7 days',
                  maxLines: compact ? 2 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: _AdminColors.muted,
                    fontSize: compact ? 12 : 14,
                  ),
                ),
              ],
            ),
          ),
          SizedBox(width: compact ? 2 : 14),
          const Icon(Icons.chevron_right_rounded, color: _AdminColors.muted),
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({
    required this.label,
    required this.value,
    required this.compact,
  });

  final String label;
  final String value;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: _AdminColors.muted,
            fontSize: compact ? 16 : 18,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            color: _AdminColors.navy,
            fontSize: compact ? 28 : 34,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _FormatButton extends StatelessWidget {
  const _FormatButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String subtitle;
  final IconData icon;
  final String value;
  final bool selected;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = MediaQuery.sizeOf(context).width <= 520;
        final width =
            compact
                ? constraints.maxWidth
                : math.min(280.0, constraints.maxWidth);
        return SizedBox(
          width: width,
          child: InkWell(
            onTap: () => onTap(value),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: EdgeInsets.all(compact ? 12 : 14),
              decoration: BoxDecoration(
                color:
                    selected
                        ? _AdminColors.green.withOpacity(0.06)
                        : Colors.white,
                border: Border.all(
                  color: selected ? _AdminColors.green : _AdminColors.border,
                  width: selected ? 1.5 : 1,
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  _SoftIcon(
                    icon: icon,
                    color: _AdminColors.green,
                    size: compact ? 38 : 44,
                  ),
                  SizedBox(width: compact ? 10 : 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: const TextStyle(
                            color: _AdminColors.navy,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(color: _AdminColors.muted),
                        ),
                      ],
                    ),
                  ),
                  if (selected)
                    const Icon(
                      Icons.check_circle_rounded,
                      color: _AdminColors.green,
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RecordFilterControls extends StatelessWidget {
  const _RecordFilterControls({
    required this.selectedFilter,
    required this.onFilterChanged,
    required this.selectedDateRange,
    required this.onDateRangePressed,
    required this.onClearDateRange,
  });

  final String selectedFilter;
  final ValueChanged<String> onFilterChanged;
  final DateTimeRange? selectedDateRange;
  final VoidCallback onDateRangePressed;
  final VoidCallback onClearDateRange;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 520;
    final filters = const ['All', 'Positive', 'Negative'];
    return SizedBox(
      height: compact ? 50 : 54,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: filters.length,
              separatorBuilder: (_, __) => SizedBox(width: compact ? 8 : 12),
              itemBuilder: (context, index) {
                final filter = filters[index];
                return _FilterChipButton(
                  label: filter,
                  selected: selectedFilter == filter,
                  color: _filterColor(filter),
                  onTap: () => onFilterChanged(filter),
                );
              },
            ),
          ),
          SizedBox(width: compact ? 8 : 12),
          _DateRangeButton(
            range: selectedDateRange,
            onPressed: onDateRangePressed,
            onClear: onClearDateRange,
            compactWidth: true,
          ),
        ],
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width <= 520;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        height: compact ? 46 : 50,
        alignment: Alignment.center,
        padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 22),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.1) : Colors.white,
          border: Border.all(color: selected ? color : color.withOpacity(0.25)),
          borderRadius: BorderRadius.circular(8),
          boxShadow:
              selected
                  ? [
                    BoxShadow(
                      color: color.withOpacity(0.16),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    ),
                  ]
                  : null,
        ),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _ResultPill extends StatelessWidget {
  const _ResultPill({required this.result});

  final String result;

  @override
  Widget build(BuildContext context) {
    final color = switch (result) {
      'Positive' => _AdminColors.green,
      'Negative' => _AdminColors.red,
      'Clear' => _AdminColors.blue,
      _ => _AdminColors.orange,
    };
    return _Pill(text: result.isEmpty ? 'Pending' : result, color: color);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        border: Border.all(color: color.withOpacity(0.2)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _SoftIcon extends StatelessWidget {
  const _SoftIcon({required this.icon, required this.color, this.size = 46});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withOpacity(0.11),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(icon, color: color, size: size * 0.46),
    );
  }
}

class _PersonAvatar extends StatelessWidget {
  const _PersonAvatar({required this.name, this.radius = 26});

  final String name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final seed = name.codeUnits.fold<int>(0, (total, code) => total + code);
    final colors = [
      _AdminColors.blue,
      _AdminColors.green,
      _AdminColors.orange,
      _AdminColors.purple,
      _AdminColors.teal,
    ];
    final color = colors[seed % colors.length];
    return CircleAvatar(
      radius: radius,
      backgroundColor: color.withOpacity(0.13),
      child: Text(
        _initials(name),
        style: TextStyle(color: color, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _DateRangeButton extends StatelessWidget {
  const _DateRangeButton({
    required this.range,
    required this.onPressed,
    required this.onClear,
    this.compactWidth = false,
  });

  final DateTimeRange? range;
  final VoidCallback onPressed;
  final VoidCallback onClear;
  final bool compactWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = MediaQuery.sizeOf(context).width <= 520;
        final hasRange = range != null;
        final targetWidth =
            compactWidth
                ? (compact ? 104.0 : 132.0)
                : (compact ? 250.0 : 292.0);
        final width = math.min(targetWidth, constraints.maxWidth);
        return SizedBox(
          width: width,
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onPressed,
                  icon: Icon(
                    Icons.calendar_month_rounded,
                    size: compact ? 18 : 20,
                  ),
                  label: Text(
                    _dateRangeLabel(range),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: compact ? 13 : 14),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _AdminColors.navy,
                    backgroundColor: Colors.white,
                    minimumSize: Size.fromHeight(
                      compactWidth ? (compact ? 46 : 50) : (compact ? 50 : 54),
                    ),
                    padding: EdgeInsets.symmetric(
                      horizontal:
                          compactWidth
                              ? (compact ? 8 : 10)
                              : (compact ? 12 : 16),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
              if (hasRange) ...[
                const SizedBox(width: 8),
                SizedBox(
                  width: compact ? 44 : 48,
                  height:
                      compactWidth ? (compact ? 46 : 50) : (compact ? 50 : 54),
                  child: OutlinedButton(
                    onPressed: onClear,
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.zero,
                      foregroundColor: _AdminColors.red,
                      backgroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Icon(Icons.close_rounded, size: 20),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MiniSelect extends StatelessWidget {
  const _MiniSelect({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        border: Border.all(color: _AdminColors.border),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(color: _AdminColors.muted)),
          const SizedBox(width: 8),
          const Icon(Icons.keyboard_arrow_down_rounded, size: 18),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 11,
          height: 11,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 9),
        Text(label, style: const TextStyle(color: _AdminColors.navy)),
      ],
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return _Card(
      child: SizedBox(
        height: 150,
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: _AdminColors.muted, fontSize: 16),
          ),
        ),
      ),
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 110,
      child: Center(
        child: Text(message, style: const TextStyle(color: _AdminColors.muted)),
      ),
    );
  }
}

class _LineChartPainter extends CustomPainter {
  _LineChartPainter(this.values);

  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    final axisPaint =
        Paint()
          ..color = _AdminColors.border
          ..strokeWidth = 1;
    final linePaint =
        Paint()
          ..color = _AdminColors.blue
          ..strokeWidth = 3
          ..style = PaintingStyle.stroke;
    final fillPaint =
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              _AdminColors.blue.withOpacity(0.22),
              _AdminColors.blue.withOpacity(0),
            ],
          ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    final dotPaint = Paint()..color = _AdminColors.blue;
    final chartHeight = size.height - 28;
    final maxValue = math.max(values.fold<int>(1, math.max), 1);
    final points = <Offset>[];

    for (var i = 0; i <= 4; i++) {
      final y = chartHeight * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), axisPaint);
    }

    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / math.max(values.length - 1, 1);
      final y = chartHeight - (chartHeight * values[i] / maxValue);
      points.add(Offset(x, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final fillPath =
        Path.from(path)
          ..lineTo(points.last.dx, chartHeight)
          ..lineTo(points.first.dx, chartHeight)
          ..close();
    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);
    for (final point in points) {
      canvas.drawCircle(point, 5, dotPaint);
    }

    final textPainter = TextPainter(textDirection: TextDirection.ltr);
    final labelIndexes =
        values.length <= 7
            ? List<int>.generate(values.length, (index) => index)
            : <int>[0, values.length ~/ 2, values.length - 1];
    for (final index in labelIndexes) {
      final label =
          values.length <= 7
              ? const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][index]
              : 'Day ${index + 1}';
      textPainter.text = TextSpan(
        text: label,
        style: const TextStyle(color: _AdminColors.muted, fontSize: 11),
      );
      textPainter.layout();
      final x = size.width * index / math.max(values.length - 1, 1);
      textPainter.paint(
        canvas,
        Offset(x - textPainter.width / 2, size.height - 16),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.values != values;
  }
}

class _DonutPainter extends CustomPainter {
  _DonutPainter({required this.negative, required this.positive});

  final int negative;
  final int positive;

  @override
  void paint(Canvas canvas, Size size) {
    final total = math.max(negative + positive, 1);
    final center = size.center(Offset.zero);
    final radius = math.min(size.width, size.height) * 0.34;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint =
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 42
          ..strokeCap = StrokeCap.butt;
    paint.color = _AdminColors.red;
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, paint);
    paint.color = _AdminColors.green;
    canvas.drawArc(
      rect,
      -math.pi / 2,
      math.pi * 2 * (positive / total),
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.negative != negative || oldDelegate.positive != positive;
  }
}

class _AdminPage {
  const _AdminPage(this.name, this.title, this.icon);

  final String name;
  final String title;
  final IconData icon;
}

class _MetricData {
  const _MetricData(this.label, this.value, this.icon, this.color);

  final String label;
  final int value;
  final IconData icon;
  final Color color;
}

class _RecordStats {
  _RecordStats(this.records);

  final List<DatasetRecordModel> records;

  int get total => records.length;
  int get positive =>
      records.where((r) => r.selectedResult == 'Positive').length;
  int get negative =>
      records.where((r) => r.selectedResult == 'Negative').length;
}

class _AdminColors {
  static const page = Color(0xFFF8FAFD);
  static const navy = Color(0xFF07143D);
  static const muted = Color(0xFF657395);
  static const border = Color(0xFFE2E8F0);
  static const blue = Color(0xFF1684F8);
  static const green = Color(0xFF00A878);
  static const red = Color(0xFFFF3B3F);
  static const orange = Color(0xFFF97316);
  static const purple = Color(0xFF6D3FD1);
  static const teal = Color(0xFF1FB7A6);
}

List<int> _weeklyCounts(List<DatasetRecordModel> records, int days) {
  final safeDays = days.clamp(7, 30);
  final counts = List<int>.filled(safeDays, 0);
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final start = today.subtract(Duration(days: safeDays - 1));
  for (final record in records) {
    final date = record.submittedAt ?? record.createdAt;
    if (date == null) continue;
    final day = DateTime(date.year, date.month, date.day);
    final index = day.difference(start).inDays;
    if (index < 0 || index >= safeDays) continue;
    counts[index] += 1;
  }
  return counts;
}

Color _filterColor(String filter) {
  return switch (filter) {
    'Positive' => _AdminColors.green,
    'Negative' => _AdminColors.red,
    _ => _AdminColors.blue,
  };
}

String _displayName(DatasetRecordModel record) {
  return record.userName.trim();
}

String _testName(DatasetRecordModel record) {
  return record.kitDisplayName;
}

String _shortId(DatasetRecordModel record) {
  if (record.recordId.length <= 10) return record.recordId;
  return 'RT-${record.recordId.substring(0, 8).toUpperCase()}';
}

String _dateTime(DatasetRecordModel record) {
  final date = record.submittedAt ?? record.createdAt;
  return DatasetRecordModel.formatDigitalDateTime(
    date,
    fallback: 'Not provided',
  );
}

String _initials(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
  if (parts.isEmpty) return 'A';
  return parts.take(2).map((p) => p[0].toUpperCase()).join();
}

String _formatCount(int value) {
  final text = value.toString();
  if (text.length <= 3) return text;
  final buffer = StringBuffer();
  for (var i = 0; i < text.length; i++) {
    if (i > 0 && (text.length - i) % 3 == 0) buffer.write(',');
    buffer.write(text[i]);
  }
  return buffer.toString();
}

String _percent(int value, int total) {
  if (total <= 0) return '0%';
  return '${(value / total * 100).toStringAsFixed(1)}%';
}

int _newestFirst(DatasetRecordModel a, DatasetRecordModel b) {
  final aDate =
      a.createdAt ?? a.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  final bDate =
      b.createdAt ?? b.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0);
  return bDate.compareTo(aDate);
}
