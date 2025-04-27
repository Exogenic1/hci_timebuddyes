import 'package:flutter/material.dart';
import 'package:table_calendar/table_calendar.dart';

class CalendarContent extends StatelessWidget {
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final CalendarFormat calendarFormat;
  final List<Map<String, dynamic>> Function(DateTime) getEventsForDay;
  final Function(DateTime, DateTime) onDaySelected;
  final Function(CalendarFormat) onFormatChanged;
  final Function(DateTime) onPageChanged;
  final bool isLeader;
  final VoidCallback onAddTask;
  final Widget? taskList;

  const CalendarContent({
    super.key,
    required this.focusedDay,
    required this.selectedDay,
    required this.calendarFormat,
    required this.getEventsForDay,
    required this.onDaySelected,
    required this.onFormatChanged,
    required this.onPageChanged,
    required this.isLeader,
    required this.onAddTask,
    required this.taskList,
  });

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isKeyboardOpen = mediaQuery.viewInsets.bottom > 0;
    final availableHeight = mediaQuery.size.height -
        mediaQuery.padding.top -
        mediaQuery.padding.bottom -
        mediaQuery.viewInsets.bottom;

    return LayoutBuilder(builder: (context, constraints) {
      double maxCalendarHeight = isKeyboardOpen
          ? constraints.maxHeight * 0.5
          : constraints.maxHeight * 0.6;

      maxCalendarHeight = maxCalendarHeight.clamp(200, double.infinity);

      return Column(
        children: [
          // Leader indicator
          if (isLeader)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.amber.shade100,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.amber),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, size: 16, color: Colors.amber.shade800),
                  const SizedBox(width: 6),
                  Text(
                    'You are the group leader',
                    style: TextStyle(
                      color: Colors.amber.shade900,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

          Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: maxCalendarHeight,
                minHeight: 200,
              ),
              child: SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: TableCalendar(
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2030, 12, 31),
                  focusedDay: focusedDay,
                  calendarFormat:
                      isKeyboardOpen ? CalendarFormat.week : calendarFormat,
                  selectedDayPredicate: (day) => isSameDay(selectedDay, day),
                  onDaySelected: onDaySelected,
                  onFormatChanged: onFormatChanged,
                  onPageChanged: onPageChanged,
                  eventLoader: getEventsForDay,
                  calendarStyle: CalendarStyle(
                    markerDecoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                    ),
                    markerSize: 8,
                    markerMargin: const EdgeInsets.symmetric(horizontal: 1),
                    todayDecoration: BoxDecoration(
                      color: Theme.of(context).primaryColor.withOpacity(0.3),
                      shape: BoxShape.circle,
                    ),
                    selectedDecoration: BoxDecoration(
                      color: Theme.of(context).primaryColor,
                      shape: BoxShape.circle,
                    ),
                  ),
                  headerStyle: HeaderStyle(
                    formatButtonVisible: !isKeyboardOpen,
                    titleCentered: true,
                    formatButtonDecoration: BoxDecoration(
                      border: Border.all(color: Theme.of(context).primaryColor),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    formatButtonTextStyle:
                        TextStyle(color: Theme.of(context).primaryColor),
                  ),
                ),
              ),
            ),
          ),

          // Task list header with selected date
          if (selectedDay != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Tasks for ${selectedDay!.month}/${selectedDay!.day}/${selectedDay!.year}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  if (isLeader)
                    IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: onAddTask,
                      tooltip: 'Add Task',
                    ),
                ],
              ),
            ),

          // Task list content
          Expanded(
            child: taskList ??
                const Center(
                  child: Text(
                    'Select a date to view tasks',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
          ),
        ],
      );
    });
  }
}
