import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/responsive_layout.dart';
import '../../../core/widgets/role_english_ltr_scope.dart';
import '../../../services/admin_notification_service.dart';

class AdminNotificationSenderScreen extends StatefulWidget {
  const AdminNotificationSenderScreen({super.key});

  @override
  State<AdminNotificationSenderScreen> createState() =>
      _AdminNotificationSenderScreenState();
}

class _AdminNotificationSenderScreenState
    extends State<AdminNotificationSenderScreen> {
  final _service = AdminNotificationService();
  final _formKey = GlobalKey<FormState>();
  final _searchController = TextEditingController();
  final _titleController = TextEditingController();
  final _bodyController = TextEditingController();

  AdminNotificationTargetType _targetType =
      AdminNotificationTargetType.allPatients;
  AdminNotificationRecipient? _selectedRecipient;
  AdminNotificationPreview? _preview;
  List<AdminNotificationRecipient> _searchResults = const [];

  Timer? _searchDebounce;
  bool _isSearching = false;
  bool _isPreviewLoading = false;
  bool _isSending = false;
  String? _errorText;
  String? _previewErrorText;
  String? _successText;
  String? _completedSearchQuery;
  int _previewRequestId = 0;

  @override
  void initState() {
    super.initState();
    _titleController.addListener(_onTextChanged);
    _bodyController.addListener(_onTextChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreview());
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _titleController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  void _onTextChanged() {
    if (mounted) setState(() {});
  }

  String _friendlyError(Object error) {
    if (error is FirebaseFunctionsException) {
      final message = error.message?.trim();
      if (message == null || message.isEmpty || message == 'internal') {
        return 'The notification service could not complete this request. Please try again after the backend is updated.';
      }
      return message;
    }
    return 'Something went wrong. Please try again.';
  }

  void _changeTarget(AdminNotificationTargetType targetType) {
    if (_targetType == targetType) return;
    setState(() {
      _previewRequestId++;
      _targetType = targetType;
      _selectedRecipient = null;
      _searchResults = const [];
      _completedSearchQuery = null;
      _preview = null;
      _isPreviewLoading = false;
      _errorText = null;
      _previewErrorText = null;
      _successText = null;
      _searchController.clear();
    });
    _loadPreview();
  }

  Future<void> _loadPreview() async {
    final selected = _selectedRecipient;
    if (_targetType.requiresRecipient && selected == null) {
      _previewRequestId++;
      setState(() {
        _preview = null;
        _isPreviewLoading = false;
        _previewErrorText = null;
      });
      return;
    }

    final requestId = ++_previewRequestId;
    setState(() {
      _isPreviewLoading = true;
      _errorText = null;
      _previewErrorText = null;
    });

    try {
      final preview = await _service.previewRecipients(
        targetType: _targetType,
        targetUserId: selected?.uid,
      );
      if (!mounted || requestId != _previewRequestId) return;
      setState(() => _preview = preview);
    } catch (e) {
      if (!mounted || requestId != _previewRequestId) return;
      setState(() {
        _preview = null;
        _previewErrorText = _friendlyError(e);
        _errorText = _previewErrorText;
      });
    } finally {
      if (mounted && requestId == _previewRequestId) {
        setState(() => _isPreviewLoading = false);
      }
    }
  }

  void _onSearchChanged(String query) {
    _searchDebounce?.cancel();
    final trimmed = query.trim();
    final selected = _selectedRecipient;
    if (selected != null && trimmed != selected.name.trim()) {
      _previewRequestId++;
      setState(() {
        _selectedRecipient = null;
        _preview = null;
        _isPreviewLoading = false;
        _successText = null;
        _previewErrorText = null;
        _completedSearchQuery = null;
      });
    }

    if (!_targetType.requiresRecipient || trimmed.length < 2) {
      setState(() {
        _searchResults = const [];
        _completedSearchQuery = null;
        _isSearching = false;
      });
      return;
    }

    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      setState(() {
        _isSearching = true;
        _errorText = null;
        _completedSearchQuery = null;
      });
      try {
        final results = await _service.searchRecipients(
          targetType: _targetType,
          query: trimmed,
        );
        if (!mounted || _searchController.text.trim() != trimmed) return;
        setState(() {
          _searchResults = results;
          _completedSearchQuery = trimmed;
        });
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _searchResults = const [];
          _completedSearchQuery = trimmed;
          _errorText = _friendlyError(e);
        });
      } finally {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  void _selectRecipient(AdminNotificationRecipient recipient) {
    setState(() {
      _selectedRecipient = recipient;
      _searchResults = const [];
      _completedSearchQuery = null;
      _searchController.text = recipient.name;
      _successText = null;
      _errorText = null;
    });
    _loadPreview();
  }

  Future<bool> _confirmSend(AdminNotificationPreview preview) async {
    final targetLabel = preview.targetLabel.isNotEmpty
        ? preview.targetLabel
        : _targetType.label;
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();

    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Confirm notification'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _dialogLine('Target', targetLabel),
                  _dialogLine('Recipients', '${preview.recipientCount}'),
                  const SizedBox(height: 12),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(body),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.pop(context, true),
                icon: const Icon(Icons.send),
                label: const Text('Send now'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Widget _dialogLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    setState(() {
      _errorText = null;
      _successText = null;
    });

    if (!_formKey.currentState!.validate()) return;
    if (_targetType.requiresRecipient && _selectedRecipient == null) {
      setState(() => _errorText = 'Select a recipient before sending.');
      return;
    }

    AdminNotificationPreview preview;
    try {
      preview = await _service.previewRecipients(
        targetType: _targetType,
        targetUserId: _selectedRecipient?.uid,
      );
      if (!mounted) return;
      setState(() {
        _preview = preview;
        _previewErrorText = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _previewErrorText = _friendlyError(e);
        _errorText = _previewErrorText;
      });
      return;
    }

    if (preview.recipientCount <= 0) {
      setState(() => _errorText = 'No active recipients matched this target.');
      return;
    }

    final confirmed = await _confirmSend(preview);
    if (!confirmed || !mounted) return;

    setState(() => _isSending = true);
    try {
      final result = await _service.sendNotification(
        targetType: _targetType,
        targetUserId: _selectedRecipient?.uid,
        title: _titleController.text,
        body: _bodyController.text,
      );
      if (!mounted) return;
      final successText =
          'Sent to ${result.recipientCount} recipient${result.recipientCount == 1 ? '' : 's'}.';
      _titleController.clear();
      _bodyController.clear();
      setState(() {
        _successText = successText;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: AppColors.success,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _errorText = _friendlyError(e));
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return RoleEnglishLtrScope(
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Send Notification'),
          centerTitle: true,
        ),
        body: ResponsivePage(
          maxWidth: 1040,
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildTargetSection(isDark),
                const SizedBox(height: 18),
                if (_targetType.requiresRecipient) ...[
                  _buildRecipientSearch(isDark),
                  const SizedBox(height: 18),
                ],
                _buildComposer(isDark),
                const SizedBox(height: 18),
                _buildPreview(isDark),
                const SizedBox(height: 18),
                if (_errorText != null)
                  _StatusBanner(
                    text: _errorText!,
                    color: AppColors.error,
                    icon: Icons.error_outline,
                  ),
                if (_successText != null)
                  _StatusBanner(
                    text: _successText!,
                    color: AppColors.success,
                    icon: Icons.check_circle_outline,
                  ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: _isSending ? null : _send,
                    icon: _isSending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    label: Text(_isSending ? 'Sending...' : 'Review and send'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTargetSection(bool isDark) {
    return _Panel(
      isDark: isDark,
      title: 'Recipients',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: AdminNotificationTargetType.values.map((targetType) {
          final selected = targetType == _targetType;
          final titleColor =
              isDark ? AppColors.textPrimaryDark : AppColors.textPrimaryLight;
          final subtitleColor = selected
              ? (isDark ? AppColors.primaryLight : AppColors.primary)
              : (isDark
                  ? AppColors.textSecondaryDark
                  : AppColors.textSecondaryLight);
          return ChoiceChip(
            selected: selected,
            checkmarkColor: titleColor,
            labelStyle: TextStyle(color: titleColor),
            label: SizedBox(
              width: 170,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    targetType.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: titleColor),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    targetType.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: subtitleColor,
                    ),
                  ),
                ],
              ),
            ),
            onSelected: (_) => _changeTarget(targetType),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            selectedColor: AppColors.primary.withValues(alpha: 0.14),
            side: BorderSide(
              color: selected
                  ? AppColors.primary
                  : (isDark ? Colors.white12 : Colors.black12),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildRecipientSearch(bool isDark) {
    return _Panel(
      isDark: isDark,
      title: _targetType == AdminNotificationTargetType.singlePatient
          ? 'Select patient'
          : 'Select doctor',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(
              hintText: _targetType == AdminNotificationTargetType.singlePatient
                  ? 'Search active students or staff...'
                  : 'Search active doctors...',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _isSearching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : (_searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            _previewRequestId++;
                            setState(() {
                              _searchController.clear();
                              _selectedRecipient = null;
                              _searchResults = const [];
                              _completedSearchQuery = null;
                              _preview = null;
                              _isPreviewLoading = false;
                              _previewErrorText = null;
                              _successText = null;
                            });
                          },
                        )
                      : null),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          if (_selectedRecipient != null) ...[
            const SizedBox(height: 10),
            _RecipientTile(
              recipient: _selectedRecipient!,
              selected: true,
              onTap: () {},
            ),
          ],
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 10),
            ..._searchResults.map(
              (recipient) => _RecipientTile(
                recipient: recipient,
                selected: recipient.uid == _selectedRecipient?.uid,
                onTap: () => _selectRecipient(recipient),
              ),
            ),
          ],
          if (_targetType.requiresRecipient &&
              _searchController.text.trim().length >= 2 &&
              _completedSearchQuery == _searchController.text.trim() &&
              !_isSearching &&
              _searchResults.isEmpty &&
              _selectedRecipient == null) ...[
            const SizedBox(height: 10),
            Text(
              'No active recipients found.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: isDark
                        ? AppColors.textSecondaryDark
                        : AppColors.textSecondaryLight,
                  ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildComposer(bool isDark) {
    final titleLength = _titleController.text.trim().length;
    final bodyLength = _bodyController.text.trim().length;

    return _Panel(
      isDark: isDark,
      title: 'Message',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFormField(
            controller: _titleController,
            maxLength: 80,
            decoration: InputDecoration(
              labelText: 'Title',
              helperText: '$titleLength/80 characters after trimming',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.isEmpty) return 'Title is required.';
              if (trimmed.length > 80) {
                return 'Title must be 80 characters or fewer.';
              }
              return null;
            },
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: _bodyController,
            maxLength: 500,
            minLines: 5,
            maxLines: 8,
            decoration: InputDecoration(
              labelText: 'Message',
              alignLabelWithHint: true,
              helperText: '$bodyLength/500 characters after trimming',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            validator: (value) {
              final trimmed = value?.trim() ?? '';
              if (trimmed.isEmpty) return 'Message is required.';
              if (trimmed.length > 500) {
                return 'Message must be 500 characters or fewer.';
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPreview(bool isDark) {
    final preview = _preview;
    final title = _titleController.text.trim();
    final body = _bodyController.text.trim();
    final mutedColor =
        isDark ? AppColors.textSecondaryDark : AppColors.textSecondaryLight;
    final countText = preview == null
        ? (_isPreviewLoading
            ? 'Counting...'
            : (_previewErrorText != null
                ? 'Unable to count'
                : (_targetType.requiresRecipient
                    ? 'Select recipient'
                    : 'Counting...')))
        : '${preview.recipientCount} recipient${preview.recipientCount == 1 ? '' : 's'}';

    return _Panel(
      isDark: isDark,
      title: 'Preview',
      trailing: _isPreviewLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.campaign, color: AppColors.info),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  preview?.targetLabel ?? _targetType.label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                countText,
                style: TextStyle(color: mutedColor),
              ),
            ],
          ),
          const Divider(height: 28),
          Text(
            title.isEmpty ? 'Notification title' : title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            body.isEmpty ? 'The message body will appear here.' : body,
            style: TextStyle(color: body.isEmpty ? mutedColor : null),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  final bool isDark;
  final String title;
  final Widget child;
  final Widget? trailing;

  const _Panel({
    required this.isDark,
    required this.title,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? AppColors.surfaceDark : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _RecipientTile extends StatelessWidget {
  final AdminNotificationRecipient recipient;
  final bool selected;
  final VoidCallback onTap;

  const _RecipientTile({
    required this.recipient,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = recipient.role == 'doctor'
        ? AppColors.primary
        : recipient.role == 'staff'
            ? AppColors.secondary
            : AppColors.tertiary;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: color.withValues(alpha: selected ? 0.13 : 0.06),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Icon(
                    recipient.role == 'doctor'
                        ? Icons.medical_services
                        : Icons.person,
                    color: color,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        recipient.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        [
                          recipient.role,
                          if (recipient.subtitle?.isNotEmpty == true)
                            recipient.subtitle!,
                          if (recipient.email?.isNotEmpty == true)
                            recipient.email!,
                        ].join(' | '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                if (selected)
                  const Icon(Icons.check_circle, color: AppColors.success),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  final String text;
  final Color color;
  final IconData icon;

  const _StatusBanner({
    required this.text,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
