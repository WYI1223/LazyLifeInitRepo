import 'package:flutter/material.dart';
import 'package:lazynote_flutter/core/bindings/api.dart' as rust_api;

/// Result returned by [CalendarEventDialog] on submit.
class CalendarEventResult {
  const CalendarEventResult({
    required this.title,
    required this.startMs,
    required this.endMs,
  });

  final String title;
  final int startMs;
  final int endMs;
}

/// Dialog for creating or editing a calendar event.
///
/// - Create mode: [existingItem] is null, uses [initialDate] + [initialHour].
/// - Edit mode: [existingItem] pre-fills title and times.
///
/// Returns [CalendarEventResult] via `Navigator.pop` on submit, or null on cancel.
class CalendarEventDialog extends StatefulWidget {
  const CalendarEventDialog({
    super.key,
    this.existingItem,
    required this.initialDate,
    this.initialHour = 9,
  });

  /// Existing event to edit (null = create mode).
  final rust_api.AtomListItem? existingItem;

  /// Default date for new events.
  final DateTime initialDate;

  /// Default start hour for new events.
  final int initialHour;

  @override
  State<CalendarEventDialog> createState() => _CalendarEventDialogState();
}

class _CalendarEventDialogState extends State<CalendarEventDialog> {
  late final TextEditingController _titleController;
  late DateTime _selectedDate;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;
  String? _validationError;

  bool get _isEditMode => widget.existingItem != null;

  @override
  void initState() {
    super.initState();

    if (_isEditMode) {
      final item = widget.existingItem!;
      _titleController = TextEditingController(
        text: item.previewText ?? item.content.split('\n').first,
      );
      final startDt = DateTime.fromMillisecondsSinceEpoch(
        item.startAt!.toInt(),
      );
      final endDt = DateTime.fromMillisecondsSinceEpoch(item.endAt!.toInt());
      _selectedDate = DateTime(startDt.year, startDt.month, startDt.day);
      _startTime = TimeOfDay(hour: startDt.hour, minute: startDt.minute);
      _endTime = TimeOfDay(hour: endDt.hour, minute: endDt.minute);
    } else {
      _titleController = TextEditingController();
      _selectedDate = widget.initialDate;
      _startTime = TimeOfDay(hour: widget.initialHour, minute: 0);
      final endHour = (widget.initialHour + 1).clamp(0, 23);
      _endTime = TimeOfDay(hour: endHour, minute: 0);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  int _timeToMs(DateTime date, TimeOfDay time) {
    return DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    ).millisecondsSinceEpoch;
  }

  void _submit() {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _validationError = 'Title cannot be empty');
      return;
    }

    final startMs = _timeToMs(_selectedDate, _startTime);
    final endMs = _timeToMs(_selectedDate, _endTime);
    if (endMs <= startMs) {
      setState(() => _validationError = 'End time must be after start time');
      return;
    }

    Navigator.of(
      context,
    ).pop(CalendarEventResult(title: title, startMs: startMs, endMs: endMs));
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked != null) {
      setState(() => _selectedDate = picked);
    }
  }

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _startTime,
    );
    if (picked != null) {
      setState(() => _startTime = picked);
    }
  }

  Future<void> _pickEndTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _endTime,
    );
    if (picked != null) {
      setState(() => _endTime = picked);
    }
  }

  static const _monthNames = [
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

  String _formatDate(DateTime d) =>
      '${_monthNames[d.month - 1]} ${d.day}, ${d.year}';

  String _formatTime(TimeOfDay t) {
    final h = t.hour.toString().padLeft(2, '0');
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const Key('calendar_event_dialog'),
      title: Text(_isEditMode ? 'Edit Event' : 'New Event'),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const Key('calendar_event_title_field'),
              controller: _titleController,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Title',
                hintText: 'Event title',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            _buildPickerRow(
              key: const Key('calendar_event_date_picker'),
              icon: Icons.calendar_today,
              label: _formatDate(_selectedDate),
              onTap: _pickDate,
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildPickerRow(
                    key: const Key('calendar_event_start_time_picker'),
                    icon: Icons.schedule,
                    label: _formatTime(_startTime),
                    onTap: _pickStartTime,
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: Text('–'),
                ),
                Expanded(
                  child: _buildPickerRow(
                    key: const Key('calendar_event_end_time_picker'),
                    icon: Icons.schedule,
                    label: _formatTime(_endTime),
                    onTap: _pickEndTime,
                  ),
                ),
              ],
            ),
            if (_validationError != null) ...[
              const SizedBox(height: 12),
              Text(
                _validationError!,
                key: const Key('calendar_event_validation_error'),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          key: const Key('calendar_event_cancel_button'),
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('calendar_event_submit_button'),
          onPressed: _submit,
          child: Text(_isEditMode ? 'Update' : 'Create'),
        ),
      ],
    );
  }

  Widget _buildPickerRow({
    Key? key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      key: key,
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.5),
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      ),
    );
  }
}
