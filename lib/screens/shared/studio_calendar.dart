import 'package:flutter/foundation.dart';
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
    void Function(BuildContext context, CalendarDay day, DaySlot slot);

/// Общий календарь студии — один и тот же для клиента и тренера (ТЗ 1, 3).
///
/// Сетка: столбцы — дни, в каждом две ячейки «Утро» и «Вечер» одного размера.
/// Лента бесконечна в обе стороны; при открытии сегодняшний день по центру.
/// У каждого месяца свой тон фона и подпись над его днями.
///
/// Устройство (docs/09, шаг 3): `CustomScrollView` с центром на «сегодня» —
/// прошлое растёт влево, будущее вправо, строятся только видимые столбцы.
/// Без подгрузки, `jumpTo` и упругой прокрутки: на iPhone они дёргали ленту.
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
  static const double height = monthBandHeight + headerHeight + 2 * cellHeight;

  @override
  ConsumerState<StudioCalendar> createState() => _StudioCalendarState();
}

class _StudioCalendarState extends ConsumerState<StudioCalendar> {
  static const double _w = StudioCalendar.columnWidth;
  static const _futureKey = ValueKey('calendar-today-and-future');

  /// Нулевая точка ленты: смещение 0 — левый край этого дня.
  late final CalendarDay _anchor;
  ScrollController? _scroll;

  /// Страницы данных, на которые подписан календарь: видимые и по одной
  /// с каждой стороны (docs/09, шаг 2). Остальные закрываются сами.
  Set<int> _pages = {};

  /// Последние данные каждой страницы — чтобы при обновлении подписки
  /// ячейки не мигали.
  final Map<int, CalendarData> _lastData = {};

  @override
  void initState() {
    super.initState();
    _anchor = ref.read(todayProvider);
    _pages = _pagesAround(_anchor, _anchor);
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  /// Контроллер создаётся, когда известна ширина: сегодня — по центру.
  ScrollController _controllerFor(double viewport) {
    final existing = _scroll;
    if (existing != null) return existing;
    final controller = ScrollController(
      initialScrollOffset: -(viewport - _w) / 2,
    )..addListener(_updatePages);
    _pages = _visiblePages(controller.initialScrollOffset, viewport);
    return _scroll = controller;
  }

  static Set<int> _pagesAround(CalendarDay first, CalendarDay last) {
    final from = CalendarPages.of(first) - 1;
    final to = CalendarPages.of(last) + 1;
    return {for (var p = from; p <= to; p++) p};
  }

  Set<int> _visiblePages(double offset, double viewport) => _pagesAround(
    _anchor.addDays((offset / _w).floor()),
    _anchor.addDays(((offset + viewport) / _w).ceil()),
  );

  /// Видимые дни → страницы. Подписки пересобираются, только когда набор
  /// страниц изменился, а не на каждый пиксель.
  void _updatePages() {
    final scroll = _scroll;
    if (scroll == null || !scroll.hasClients) return;
    final position = scroll.position;
    if (!position.hasPixels || !position.hasViewportDimension) return;
    final pages = _visiblePages(position.pixels, position.viewportDimension);
    if (!setEquals(pages, _pages)) setState(() => _pages = pages);
  }

  @override
  Widget build(BuildContext context) {
    final today = ref.watch(todayProvider);
    final now = ref.watch(clockProvider)();
    final pageData = <int, CalendarData>{};
    for (final page in _pages) {
      final value = ref.watch(calendarPageProvider(page)).value;
      if (value != null) _lastData[page] = value;
      final data = value ?? _lastData[page];
      if (data != null) pageData[page] = data;
    }
    _lastData.removeWhere((page, _) => !_pages.contains(page));

    Widget column(CalendarDay day) => _DayColumn(
      key: ValueKey('day-${day.toKey()}'),
      mode: widget.mode,
      day: day,
      today: today,
      now: now,
      data: pageData[CalendarPages.of(day)],
      onOpen: (slot) => widget.onOpenCell(context, day, slot),
    );

    final palette = context.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.card,
        borderRadius: AppRadii.dense,
        border: Border.all(color: palette.line, width: 0.5),
      ),
      child: ClipRRect(
        borderRadius: AppRadii.dense,
        child: SizedBox(
          height: StudioCalendar.height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _RowLabels(),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final scroll = _controllerFor(constraints.maxWidth);
                    return Stack(
                      children: [
                        // Один Material на всю ленту: ячейки рисуют фон
                        // через Ink, без отдельного Material в каждой.
                        Material(
                          type: MaterialType.transparency,
                          child: CustomScrollView(
                            controller: scroll,
                            scrollDirection: Axis.horizontal,
                            center: _futureKey,
                            physics: const ClampingScrollPhysics(),
                            slivers: [
                              // Прошлое: индекс 0 — вчера, дальше влево.
                              SliverFixedExtentList(
                                itemExtent: _w,
                                delegate: SliverChildBuilderDelegate(
                                  (_, i) => column(_anchor.addDays(-1 - i)),
                                ),
                              ),
                              SliverFixedExtentList(
                                key: _futureKey,
                                itemExtent: _w,
                                delegate: SliverChildBuilderDelegate(
                                  (_, i) => column(_anchor.addDays(i)),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Positioned(
                          left: 0,
                          right: 0,
                          top: 0,
                          height: StudioCalendar.monthBandHeight,
                          child: IgnorePointer(
                            child: _MonthLabels(
                              scroll: scroll,
                              viewport: constraints.maxWidth,
                              anchor: _anchor,
                              today: today,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
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

/// Подписи месяцев над лентой. Тон месяца рисует сам столбец дня, здесь —
/// только текст: подпись «прилипает» к левому краю, пока виден хоть один
/// день месяца, и её выталкивает подпись следующего месяца.
///
/// Перестраиваются одна-две подписи, а не вся полоса (docs/09, шаг 3).
class _MonthLabels extends StatelessWidget {
  const _MonthLabels({
    required this.scroll,
    required this.viewport,
    required this.anchor,
    required this.today,
  });

  final ScrollController scroll;
  final double viewport;
  final CalendarDay anchor;
  final CalendarDay today;

  static const double _labelWidth = 110;
  static const double _inset = 8;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelMedium?.copyWith(
      color: context.colors.onSurface,
      fontWeight: FontWeight.w700,
    );
    const w = StudioCalendar.columnWidth;

    return ListenableBuilder(
      listenable: scroll,
      builder: (context, _) {
        // До первой раскладки позиции ещё нет — берём начальное смещение.
        final offset = scroll.hasClients && scroll.position.hasPixels
            ? scroll.position.pixels
            : scroll.initialScrollOffset;
        final first = anchor.addDays((offset / w).floor());
        final last = anchor.addDays(((offset + viewport) / w).floor());

        // Месяцы, попавшие в видимую часть, и x начала каждого.
        final labels = <Widget>[];
        var month = DateTime(first.year, first.month);
        while (!DateTime(last.year, last.month).isBefore(month)) {
          final start = CalendarDay(month.year, month.month, 1);
          final next = DateTime(month.year, month.month + 1);
          final nextStart = CalendarDay(next.year, next.month, 1);
          final startX = start.daysSince(anchor) * w - offset;
          final endX = nextStart.daysSince(anchor) * w - offset;
          final left = startX + _inset < _inset
              ? _inset.clamp(-double.infinity, endX - _labelWidth)
              : startX + _inset;
          labels.add(
            Positioned(
              left: left,
              top: 0,
              bottom: 0,
              child: Center(
                child: Text(
                  month.year == today.year
                      ? RuFormat.monthName(month.month)
                      : '${RuFormat.monthName(month.month)} ${month.year}',
                  style: style,
                ),
              ),
            ),
          );
          month = next;
        }
        return ClipRect(child: Stack(children: labels));
      },
    );
  }
}

class _DayColumn extends StatelessWidget {
  const _DayColumn({
    super.key,
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

    return Column(
      children: [
        // Полоса месяца над днём — тон месяца без затемнения прошлого.
        SizedBox(
          height: StudioCalendar.monthBandHeight,
          child: ColoredBox(color: tone),
        ),
        Expanded(
          child: Container(
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
                    // Тренер: пустая ячейка сегодня и дальше — «+».
                    canCreate:
                        mode == CalendarMode.trainer &&
                        data != null &&
                        !day.isBefore(today),
                    onTap: () => onOpen(slot),
                  ),
              ],
            ),
          ),
        ),
      ],
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

    final shape = RoundedRectangleBorder(
      borderRadius: AppRadii.dense,
      side: border == null
          ? BorderSide.none
          : BorderSide(color: border, width: 0.8),
    );

    return SizedBox(
      height: StudioCalendar.cellHeight,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Ink(
          decoration: ShapeDecoration(
            color: fill ?? Colors.transparent,
            shape: shape,
          ),
          child: InkWell(
            customBorder: shape,
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
