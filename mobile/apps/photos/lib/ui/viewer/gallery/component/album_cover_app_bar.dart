import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:flutter/rendering.dart";
import "package:flutter/services.dart";
import "package:hugeicons/hugeicons.dart";
import "package:intl/intl.dart";
import "package:photos/core/constants.dart";
import "package:photos/core/page_route_observer.dart";
import "package:photos/models/collection/collection.dart";
import "package:photos/models/file/file.dart";
import "package:photos/services/collections_service.dart";
import "package:photos/ui/viewer/file/thumbnail_widget.dart";

// Figma: https://www.figma.com/design/BuBNPPytxlVnqfmCUW0mgz/Ente-Visual-Design?node-id=25285-293816&m=dev
class AlbumCoverAppBar extends StatefulWidget {
  const AlbumCoverAppBar({
    super.key,
    required this.collection,
    required this.cover,
    required this.title,
    required this.actionsBuilder,
    required this.coverActions,
    required this.backgroundColor,
    required this.collapsedHeight,
    this.bottom,
  });

  final Collection collection;
  final EnteFile cover;
  final String title;
  final List<Widget> Function(Color foregroundColor) actionsBuilder;
  final List<Widget> coverActions;
  final Color backgroundColor;
  final double collapsedHeight;
  final PreferredSizeWidget? bottom;

  static HeaderAppBarGeometry resolveGeometry(
    BuildContext context, {
    required double collapsedHeight,
    required double bottomHeight,
  }) {
    final topPadding = MediaQuery.paddingOf(context).top;
    return HeaderAppBarGeometry(
      minExtent: topPadding + collapsedHeight + bottomHeight,
      maxExtent: topPadding + _coverHeight + _coverBottomInset(bottomHeight),
    );
  }

  @override
  State<AlbumCoverAppBar> createState() => _AlbumCoverAppBarState();
}

class _AlbumCoverAppBarState extends State<AlbumCoverAppBar> with RouteAware {
  late SystemUiOverlayStyle _pinnedOverlayStyle;
  bool _isCovered = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final isDarkTheme = Theme.of(context).brightness == Brightness.dark;
    _pinnedOverlayStyle = SystemUiOverlayStyle(
      statusBarIconBrightness: isDarkTheme ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDarkTheme ? Brightness.dark : Brightness.light,
    );
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      pageRouteObserver.subscribe(this, route);
    }
  }

  // The page below stays painted, so its style region would keep applying
  // the cover's light style to the page above it.
  @override
  void didPushNext() {
    setState(() => _isCovered = true);
  }

  @override
  void didPopNext() {
    setState(() => _isCovered = false);
  }

  @override
  void dispose() {
    pageRouteObserver.unsubscribe(this);
    // Pages without their own overlay style would keep the cover's light one.
    SystemChrome.setSystemUIOverlayStyle(_pinnedOverlayStyle);
    WidgetsBinding.instance.scheduleFrame();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.componentColors;
    final bottomHeight = widget.bottom?.preferredSize.height ?? 0;
    final description = widget.collection.displayDescription;

    return SliverPersistentHeader(
      pinned: true,
      delegate: _AlbumCoverDelegate(
        geometry: AlbumCoverAppBar.resolveGeometry(
          context,
          collapsedHeight: widget.collapsedHeight,
          bottomHeight: bottomHeight,
        ),
        topPadding: MediaQuery.paddingOf(context).top,
        collapsedHeight: widget.collapsedHeight,
        bottomHeight: bottomHeight,
        colors: colors,
        backgroundColor: widget.backgroundColor,
        pinnedOverlayStyle: _pinnedOverlayStyle,
        isCovered: _isCovered,
        title: widget.title,
        actionsBuilder: widget.actionsBuilder,
        bottom: widget.bottom,
        photo: _CoverPhoto(
          cover: widget.cover,
          backgroundColor: widget.backgroundColor,
        ),
        content: SizedBox(
          width: MediaQuery.sizeOf(context).width - Spacing.lg * 2,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              const Positioned(
                left: -_contentScrimOutset,
                right: -_contentScrimOutset,
                top: -_contentScrimOutset,
                bottom: -_contentScrimOutset,
                child: IgnorePointer(
                  child: FittedBox(
                    fit: BoxFit.fill,
                    child: SizedBox.square(
                      dimension: 1,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            colors: [_scrimColor, _transparentScrimColor],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _CoverCaption(widget.collection),
                  Semantics(
                    header: true,
                    child: Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyles.display1.copyWith(
                        color: colors.specialWhite,
                      ),
                    ),
                  ),
                  if (description != null) ...[
                    const SizedBox(height: Spacing.sm),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Spacing.lg,
                      ),
                      child: Text(
                        description,
                        maxLines: _descriptionMaxLines,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyles.mini.copyWith(
                          color: colors.specialWhite.withValues(alpha: 0.92),
                        ),
                      ),
                    ),
                  ],
                  if (widget.coverActions.isNotEmpty) ...[
                    const SizedBox(height: Spacing.md),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      spacing: Spacing.md,
                      children: widget.coverActions,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class AlbumCoverActionButton extends StatelessWidget {
  const AlbumCoverActionButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final List<List<dynamic>> icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: _coverActionSize,
            height: _coverActionSize,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [_coverActionFillColor, _scrimColor],
              ),
            ),
            child: HugeIcon(
              icon: icon,
              size: _coverActionIconSize,
              color: context.componentColors.specialWhite,
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverPhoto extends StatelessWidget {
  const _CoverPhoto({required this.cover, required this.backgroundColor});

  final EnteFile cover;
  final Color backgroundColor;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      clipBehavior: Clip.none,
      children: [
        ThumbnailWidget(
          cover,
          rawThumbnail: true,
          thumbnailSize: thumbnailLargeSize,
          useRequestedThumbnailSizeForLocalCache: true,
        ),
        const ColoredBox(color: _photoScrimColor),
        // Overshoots the photo so its antialiased edge cannot show through.
        Positioned(
          left: 0,
          right: 0,
          bottom: -_coverDissolveOvershoot,
          height: _coverDissolveHeight + _coverDissolveOvershoot,
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [backgroundColor.withValues(alpha: 0), backgroundColor],
                stops: const [
                  0,
                  _coverDissolveHeight /
                      (_coverDissolveHeight + _coverDissolveOvershoot),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CoverCaption extends StatelessWidget {
  const _CoverCaption(this.collection);

  final Collection collection;

  Future<({int count, int? newestFileTime})> _loadSummary() async {
    final collectionsService = CollectionsService.instance;
    final count = await collectionsService.getFileCount(collection);
    final newestFileTimes = await collectionsService
        .getCollectionIDToNewestFileTime();
    return (count: count, newestFileTime: newestFileTimes[collection.id]);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _loadSummary(),
      builder: (context, snapshot) {
        final summary = snapshot.data;
        if (summary == null) {
          return const SizedBox.shrink();
        }

        final newestFileTime = summary.newestFileTime;
        final caption = [
          context.strings.memoryCount(
            count: summary.count,
            formattedCount: NumberFormat().format(summary.count),
          ),
          if (newestFileTime != null)
            DateFormat.yMMM(
              Localizations.localeOf(context).languageCode,
            ).format(DateTime.fromMicrosecondsSinceEpoch(newestFileTime)),
        ].join(" · ");

        return Padding(
          padding: const EdgeInsets.only(bottom: Spacing.md),
          child: DecoratedBox(
            decoration: const ShapeDecoration(
              color: _captionFillColor,
              shape: StadiumBorder(),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: Spacing.md,
                vertical: Spacing.sm,
              ),
              child: Text(
                caption.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyles.tiny.copyWith(
                  color: context.componentColors.specialWhite.withValues(
                    alpha: 0.82,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AlbumCoverDelegate extends SliverPersistentHeaderDelegate {
  const _AlbumCoverDelegate({
    required this.geometry,
    required this.topPadding,
    required this.collapsedHeight,
    required this.bottomHeight,
    required this.colors,
    required this.backgroundColor,
    required this.pinnedOverlayStyle,
    required this.isCovered,
    required this.title,
    required this.actionsBuilder,
    required this.bottom,
    required this.photo,
    required this.content,
  });

  final HeaderAppBarGeometry geometry;
  final double topPadding;
  final double collapsedHeight;
  final double bottomHeight;
  final ColorTokens colors;
  final Color backgroundColor;
  final SystemUiOverlayStyle pinnedOverlayStyle;
  final bool isCovered;
  final String title;
  final List<Widget> Function(Color foregroundColor) actionsBuilder;
  final PreferredSizeWidget? bottom;
  final Widget photo;
  final Widget content;

  @override
  double get maxExtent => geometry.maxExtent;

  @override
  double get minExtent => geometry.minExtent;

  @override
  OverScrollHeaderStretchConfiguration get stretchConfiguration =>
      _stretchConfiguration;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final collapseOffset = math.min(shrinkOffset, geometry.collapseExtent);
    final pinnedProgress =
        ((collapseOffset / geometry.collapseExtent - _pinnedFadeStart) /
                (1 - _pinnedFadeStart))
            .clamp(0.0, 1.0);
    final contentOpacity = (1 - collapseOffset / _contentFadeExtent).clamp(
      0.0,
      1.0,
    );
    final titleOpacity = (1 - contentOpacity * 2).clamp(0.0, 1.0);
    final foregroundColor = Color.lerp(
      colors.specialWhite,
      colors.textBase,
      ((pinnedProgress - _foregroundSwitchStart) /
              (_foregroundSwitchEnd - _foregroundSwitchStart))
          .clamp(0.0, 1.0),
    )!;
    final coverBottomInset = _coverBottomInset(bottomHeight);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: pinnedProgress < 0.5 && !isCovered
          ? _coverOverlayStyle
          : pinnedOverlayStyle,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(
            top: -collapseOffset,
            left: 0,
            right: 0,
            bottom: coverBottomInset,
            child: photo,
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: topPadding + _topScrimHeight,
            child: const IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [_scrimColor, _transparentScrimColor],
                  ),
                ),
              ),
            ),
          ),
          if (contentOpacity > 0)
            Positioned(
              top: topPadding + collapsedHeight,
              left: Spacing.lg,
              right: Spacing.lg,
              bottom: coverBottomInset + _contentBottomGap,
              child: Opacity(
                opacity: contentOpacity,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.bottomCenter,
                  child: content,
                ),
              ),
            ),
          if (pinnedProgress > 0)
            Positioned.fill(
              child: ColoredBox(
                color: backgroundColor.withValues(alpha: pinnedProgress),
              ),
            ),
          Positioned(
            top: topPadding,
            left: Spacing.lg,
            right: Spacing.lg,
            height: collapsedHeight,
            child: Row(
              spacing: Spacing.sm,
              children: [
                IconButtonComponent(
                  tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                  icon: HugeIcon(
                    icon: HugeIcons.strokeRoundedArrowLeft02,
                    color: foregroundColor,
                  ),
                  variant: IconButtonComponentVariant.unfilled,
                  shouldSurfaceExecutionStates: false,
                  onTap: () => Navigator.maybePop(context),
                ),
                Expanded(
                  child: ExcludeSemantics(
                    excluding: titleOpacity == 0,
                    child: Opacity(
                      opacity: titleOpacity,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyles.display3.copyWith(
                          color: foregroundColor,
                        ),
                      ),
                    ),
                  ),
                ),
                ...actionsBuilder(foregroundColor),
              ],
            ),
          ),
          if (bottom != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: bottomHeight,
              child: bottom!,
            ),
        ],
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _AlbumCoverDelegate oldDelegate) => true;
}

double _coverBottomInset(double bottomHeight) {
  return math.max(0.0, bottomHeight - _bottomOverlap);
}

const _coverHeight = 441.0;
const _coverDissolveHeight = 100.0;
const _coverDissolveOvershoot = 1.0;
const _topScrimHeight = 31.0;
const _bottomOverlap = 25.0;
const _contentBottomGap = 108.0;
const _contentScrimOutset = 56.0;
const _contentFadeExtent = 120.0;
const _pinnedFadeStart = 0.6;
const _foregroundSwitchStart = 0.4;
const _foregroundSwitchEnd = 0.6;
const _descriptionMaxLines = 3;
const _coverActionSize = 42.0;
const _coverActionIconSize = 17.0;

const _photoScrimColor = Color(0x3D000000);
const _scrimColor = Color(0x33000000);
const _transparentScrimColor = Color(0x00000000);
const _captionFillColor = Color(0x52000000);
const _coverActionFillColor = Color(0x66000000);

const _coverOverlayStyle = SystemUiOverlayStyle(
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
);

final _stretchConfiguration = OverScrollHeaderStretchConfiguration();
