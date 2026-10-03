import "package:ente_components/ente_components.dart";
import "package:flutter/material.dart";
import "package:photos/ui/components/bottom_action_bar/selection_action_button_widget.dart";

// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=25316-7380&m=dev
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
    builder: (context) {
      final colors = context.componentColors;
      return BottomSheetComponent(
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
                          child: SelectionActionButton(
                            labelText: option.label,
                            iconWidget:
                                option.leadingWidget ?? const SizedBox.shrink(),
                            isCritical: option.labelColor != null,
                            color: colors.textLight,
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
      );
    },
  );
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
