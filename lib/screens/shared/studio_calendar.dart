import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../client/calendar_cells.dart';
import '../../client/client_providers.dart';
import '../../models/models.dart';
import '../../services/backend_providers.dart';
import '../../theme/app_radii.dart';
import '../../theme/theme_context.dart';
import '../../utils/ru_format.dart';

/// Что сделать по нажатию на ячейку: экран роли открывает своё окно.
typedef CellOpener =
    void Function(
      BuildContext context,
      CalendarDay day,
      DaySlot slot,
      DayRange range,
    );

/// Общий календарь студии — один и тот же для клиента и тренера (ТЗ 1, 3).
///
/// Сетка: столбцы — дни, в каждом две ячейки «Утро» и «Вечер» одного размера.
/// Лента прокручивается по горизонтали: сначала ±30 дней от сегодня, у края
/// подгружаются следующие 30 — фактически бесконечно. При открытии сегодняшний
/// день по центру. У каждого месяца свой тон фона и подпись над его днями.
///
/// [mode] меняет только содержимое ячеек (ТЗ 3.1 / 3.2): клиент видит свои
/// записи и «Отменено», тренер — места и «+» в пустых ячейках, а отменённая
/// тренировка у него выглядит пустой ячейкой.
class StudioCalendar extends ConsumerStatefulWidget {
  const StudioCalendar({
    super.key,
    required this.mode,
    required this.onOpenCell,
  });

  final CalendarMode mode;
  final CellOpener onOpenCell;

  /// Размеры сетки — крупнее чернового макета (ТЗ 3).
  static const double columnWidth = 76;
  static const double labelWidth = 62;
  static const double monthBandHeight = 26;
  static const double headerHeight = 46;
  static const double cellHeight = 80;
  static const int pageDays = 30;

  @override
  ConsumerState<StudioCalendar> createState() => _StudioCalendarState();
}

class _StudioCalendarState extends ConsumerState<StudioCalendar> {
  static const double _w = StudioCalendar.columnWidth;

  final _scroll = ScrollController();
  late CalendarDay _from;
  late CalendarDay _to;
  CalendarData? _lastData;
  bool _centered = false;
  bool _prepending = false;

  @override
  void initState() {
    super.initState();
    final today = ref.read(todayProvider);
    _from = today.addDays(-StudioCalendar.pageDays);
    _to = today.addDays(StudioCalendar.pageDays);
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// У края ленты — ещё 30 дней. Слева после добавления сдвигаем прокрутку,
  /// чтобы видимые дни остались на месте.
  void _onScroll() {
    if (!_scroll.hasClients || !_centered) return;
    final position = _scroll.position;
    if (position.pixels > position.maxScrollExtent - _w * 6) {
      setState(() => _to = _to.addDays(StudioCalendar.pageDays));
    } else if (position.pixels < _w * 6 && !_prepending) {
      _prepending = true;
      setState(() => _from = _from.addDays(-StudioCalendar.pageDays));
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.offset + _w * StudioCalendar.pageDays);
        }
        _prepending = false;
      });
    }
  }

  void _centerToday(CalendarDay today) {
    if (_centered || !_scroll.hasClients) return;
    final viewport = _scroll.position.viewportDimension;
    final target = today.daysSince(_from) * _w - (viewport - _w) / 2;
    _scroll.jumpTo(target.clamp(0, _scroll.position.maxScrollExtent));
    _centered = true;
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final now = ref.watch(clockProvider)();
    final range = (from: _from, to: _to);
    final async = ref.watch(calendarDataProvider(range));
    // Пока подгружается новый отрезок, показываем прежние данные —
    // чтобы ячейки не мигали при прокрутке.
    final data = async.value ?? _lastData;
    if (async.hasValue) _lastData = async.value;

    final days = [for (var d = _from; !d.isAfter(_to); d = d.addDays(1)) d];
    WidgetsBinding.instance.addPostFrameCallback((_) => _centerToday(today));

    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: AppRadii.dense,
        border: Border.all(color: palette.line, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: AppRadii.dense,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _RowLabels(),
            Expanded(
              child: SingleChildScrollView(
                controller: _scroll,
                scrollDirection: Axis.horizontal,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _MonthBand(days: days, scroll: _scroll),
                    Row(
                      children: [
                        for (final day in days)
                          _DayColumn(
                            mode: widget.mode,
                            day: day,
                            today: today,
                            now: now,
                            data: data,
                            onOpen: (slot) =>
                                widget.onOpenCell(context, day, slot, range),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// «Утро» / «Вечер» слева — крупнее и плотнее второстепенного текста (ТЗ 11.2).
class _RowLabels extends StatelessWidget {
  const _RowLabels();

  @override
  Widget build(BuildContext context) {
    final style = context.textStyles.dayPart;
    Widget label(String text) => SizedBox(
      height: StudioCalendar.cellHeight,
      child: Center(child: Text(text, style: style)),
    );
    return SizedBox(
      width: StudioCalendar.labelWidth,
      child: Column(
        children: [
          const SizedBox(
            height:
                StudioCalendar.monthBandHeight + StudioCalendar.headerHeight,
          ),
          label(DaySlot.morning.label),
          label(DaySlot.evening.label),
        ],
      ),
    );
  }
}

/// Полоса месяцев: тон месяца на всю его группу дней и подпись, которая
/// «прилипает» к левому краю, пока видна хоть часть месяца.
class _MonthBand extends StatelessWidget {
  const _MonthBand({required this.days, required this.scroll});

  final List<CalendarDay> days;
  final ScrollController scroll;

  static const double _labelWidth = 110;

  @override
  Widget build(BuildContext context) {
    const w = StudioCalendar.columnWidth;
    final palette = context.palette;
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: context.colors.onSurface,
      fontWeight: FontWeight.w700,
    );

    // Группы подряд идущих дней одного месяца: (индекс первого дня, число дней).
    final groups = <(int, int, CalendarDay)>[];
    for (var i = 0; i < days.length; i++) {
      if (i == 0 || days[i].month != days[i - 1].month) {
        groups.add((i, 1, days[i]));
      } else {
        final (start, count, first) = groups.removeLast();
        groups.add((start, count + 1, first));
      }
    }
    final currentYear = days[days.length ~/ 2].year;

    return SizedBox(
      width: days.length * w,
      height: StudioCalendar.monthBandHeight,
      child: AnimatedBuilder(
        animation: scroll,
        builder: (context, _) {
          final offset = scroll.hasClients ? scroll.offset : 0.0;
          return Stack(
            children: [
              for (final (start, count, first) in groups) ...[
                Positioned(
                  left: start * w,
                  width: count * w,
                  top: 0,
                  bottom: 0,
                  child: ColoredBox(
                    color: palette.monthToneFor(
                      DateTime(first.year, first.month),
                    ),
                  ),
                ),
                Positioned(
                  left: _stickyLeft(offset, start * w, (start + count) * w),
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Text(
                      first.year == currentYear
                          ? RuFormat.monthName(first.month)
                          : '${RuFormat.monthName(first.month)} ${first.year}',
                      style: style,
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static double _stickyLeft(double offset, double groupStart, double groupEnd) {
    final min = groupStart + 8;
    final max = groupEnd - _labelWidth;
    if (max <= min) return min;
    return (offset + 8).clamp(min, max);
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    required this.mode,
    required this.day,
    required this.today,
    required this.now,
    required this.data,
    required this.onOpen,
  });

  final CalendarMode mode;
  final CalendarDay day;
  final CalendarDay today;
  final DateTime now;
  final CalendarData? data;
  final void Function(DaySlot slot) onOpen;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colors = context.colors;
    final isToday = day == today;
    final isPastDay = day.isBefore(today);
    final tone = palette.monthToneFor(DateTime(day.year, day.month));

    // Прошедшие дни слегка затемнены (ТЗ 3).
    final background = isPastDay
        ? Color.alphaBlend(colors.onSurface.withValues(alpha: 0.05), tone)
        : tone;

    return Container(
      width: StudioCalendar.columnWidth,
      color: background,
      // Сегодня — тонкая рамка вокруг всего столбца (утро + вечер).
      foregroundDecoration: isToday
          ? BoxDecoration(
              border: Border.all(color: colors.primary, width: 1.5),
              borderRadius: AppRadii.dense,
            )
          : null,
      child: Column(
        children: [
          _DayHeader(day: day, isToday: isToday),
          for (final slot in DaySlot.values)
            _CalendarCell(
              key: ValueKey('cell-${slotKeyOf(day, slot)}'),
              cell: data?.cellFor(mode, day, slot, now),
              // Тренер: пустая ячейка сегодня и дальше — «+», новая тренировка.
              canCreate:
                  mode == CalendarMode.trainer &&
                  data != null &&
                  !day.isBefore(today),
              onTap: () => onOpen(slot),
            ),
        ],
      ),
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day, required this.isToday});

  final CalendarDay day;
  final bool isToday;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final textTheme = Theme.of(context).textTheme;
    final accent = isToday ? colors.primary : colors.onSurfaceVariant;

    // Одна строка на подпись и уменьшение вместо переноса: при крупном
    // системном шрифте столбец не «разъезжается».
    return SizedBox(
      height: StudioCalendar.headerHeight,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              isToday ? 'Сегодня' : RuFormat.weekdayShort(day),
              style: textTheme.labelSmall?.copyWith(
                color: accent,
                fontWeight: FontWeight.w700,
                fontSize: 11,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              // Даты — шрифтом заголовков (ТЗ 11.2).
              isToday
                  ? '${RuFormat.weekdayShort(day)} ${day.day}'
                  : '${day.day}',
              style: textTheme.titleMedium?.copyWith(
                fontFamily: context.textStyles.counter.fontFamily,
                fontSize: 15,
                height: 1.2,
                color: isToday ? colors.primary : colors.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Ячейка: пусто («—» или «+» у тренера) / доступно / записан / отменено /
/// прошла (ТЗ 3.1, 3.2).
class _CalendarCell extends StatelessWidget {
  const _CalendarCell({
    super.key,
    required this.cell,
    required this.canCreate,
    required this.onTap,
  });

  /// `null` — данные ещё грузятся.
  final CellView? cell;

  /// Пустую ячейку можно нажать, чтобы назначить тренировку.
  final bool canCreate;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final colors = context.colors;
    final styles = context.textStyles;
    final small = Theme.of(context).textTheme.labelSmall;
    final time = small?.copyWith(
      fontFamily: styles.counter.fontFamily,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      height: 1.3,
    );

    final (
      Color? fill,
      Color? border,
      Color text,
      List<String> lines,
      bool tappable,
    ) = switch (cell) {
      EmptyCell() when canCreate => (
        null,
        palette.line,
        colors.primary,
        ['+'],
        true,
      ),
      null || EmptyCell() => (
        null,
        palette.line,
        colors.onSurfaceVariant,
        ['—'],
        false,
      ),
      CancelledCell() => (
        null,
        palette.line,
        palette.cancelled,
        const [],
        true,
      ),
      TrainingCell(:final training, isPast: true) => (
        palette.line.withValues(alpha: 0.6),
        null,
        colors.onSurfaceVariant,
        [training.startTime.format(), 'прошла'],
        true,
      ),
      TrainingCell(:final training, isBooked: true) => (
        colors.primary,
        null,
        colors.onPrimary,
        [training.startTime.format(), 'вы записаны'],
        true,
      ),
      TrainingCell(:final training) => (
        palette.bloomTint,
        null,
        colors.primary,
        [
          training.startTime.format(),
          '${training.bookedCount}/${training.capacity}',
        ],
        true,
      ),
    };

    final content = switch (cell) {
      CancelledCell() => Text(
        'Отменено',
        style: styles.cancelledLabel,
        textAlign: TextAlign.center,
      ),
      _ => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (i, line) in lines.indexed)
            Text(
              line,
              textAlign: TextAlign.center,
              style: i == 0
                  ? time?.copyWith(color: text)
                  : small?.copyWith(color: text, fontWeight: FontWeight.w600),
            ),
        ],
      ),
    };

    return SizedBox(
      height: StudioCalendar.cellHeight,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Material(
          color: fill ?? Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.dense,
            side: border == null
                ? BorderSide.none
                : BorderSide(color: border, width: 0.8),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: tappable ? onTap : null,
            child: Padding(
              padding: const EdgeInsets.all(3),
              child: Center(
                child: FittedBox(fit: BoxFit.scaleDown, child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
