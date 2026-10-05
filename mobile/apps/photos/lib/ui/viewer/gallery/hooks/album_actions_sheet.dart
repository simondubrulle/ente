import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";

Future<T?> showAlbumActionsSheet<T>(
  BuildContext context,
  List<EntePopupMenuOption<T>> options,
) {
  final criticalIndex = options.indexWhere(
    (option) => option.labelColor != null,
  );
  final tiles = [
    ...options
        .where((option) => option.labelColor == null)
        .take(criticalIndex == -1 ? _tilesPerShelf : _tilesPerShelf - 1),
    if (criticalIndex != -1) options[criticalIndex],
  ];
  final rows = options.where((option) => !tiles.contains(option)).toList();

  return showBottomSheetComponent<T>(
    context: context,
    barrierColor: context.componentColors.specialScrim.withValues(alpha: 0.4),
    builder: (context) {
      final colors = context.componentColors;
      return DecoratedBox(
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(Radii.bottomSheet),
          ),
          boxShadow: [
            BoxShadow(
              color: Color.from(alpha: 0.18, red: 0, green: 0, blue: 0),
              offset: Offset(0, -2),
              blurRadius: 80,
            ),
          ],
        ),
        child: BottomSheetComponent(
          showCloseButton: false,
          backgroundColor: colors.fillLight,
          padding: const EdgeInsets.only(top: Spacing.lg, bottom: Spacing.sm),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * _maxHeightFraction,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(
                      color: colors.textLightest,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(height: Spacing.xxl),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: Spacing.md),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      spacing: Spacing.xs,
                      children: [
                        for (final option in tiles)
                          Expanded(
                            child: _AlbumActionTile(
                              option: option,
                              onTap: () =>
                                  Navigator.of(context).pop(option.value),
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (rows.isNotEmpty)
                    const DividerComponent(
                      padding: EdgeInsets.fromLTRB(
                        Spacing.lg,
                        Spacing.lg,
                        Spacing.lg,
                        Spacing.xl,
                      ),
                    ),
                  for (final option in rows)
                    _AlbumActionRow(
                      option: option,
                      onTap: () => Navigator.of(context).pop(option.value),
                    ),
                  const SizedBox(height: Spacing.lg),
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _AlbumActionTile<T> extends StatelessWidget {
  const _AlbumActionTile({required this.option, required this.onTap});

  final EntePopupMenuOption<T> option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final foreground = option.labelColor ?? colors.textLight;
    return Semantics(
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.md),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: option.labelColor == null ? 0 : 64,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox.square(
                  dimension: 34,
                  child: Center(
                    child: IconTheme.merge(
                      data: IconThemeData(
                        color: foreground,
                        size: IconSizes.small,
                      ),
                      child: option.leadingWidget ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
                const SizedBox(height: Spacing.xs),
                Text(
                  option.label,
                  textAlign: TextAlign.center,
                  style: TextStyles.mini.copyWith(color: foreground),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AlbumActionRow<T> extends StatelessWidget {
  const _AlbumActionRow({required this.option, required this.onTap});

  final EntePopupMenuOption<T> option;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;

    return Semantics(
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.lg),
            child: Row(
              spacing: Spacing.md,
              children: [
                SizedBox.square(
                  dimension: 34,
                  child: Center(
                    child: IconTheme.merge(
                      data: IconThemeData(
                        color: option.labelColor ?? colors.textLight,
                        size: IconSizes.small,
                      ),
                      child: option.leadingWidget ?? const SizedBox.shrink(),
                    ),
                  ),
                ),
                Expanded(
                  child: Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyles.mini.copyWith(
                      color: option.labelColor ?? colors.textBase,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

const _tilesPerShelf = 4;
const _maxHeightFraction = 0.8;
