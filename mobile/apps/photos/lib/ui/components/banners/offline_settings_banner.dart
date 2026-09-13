import "dart:async";
import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/service_locator.dart";

class OfflineSettingsBanner extends StatefulWidget {
  final VoidCallback onGetStarted;

  const OfflineSettingsBanner({super.key, required this.onGetStarted});

  @override
  State<OfflineSettingsBanner> createState() => _OfflineSettingsBannerState();
}

class _OfflineSettingsBannerState extends State<OfflineSettingsBanner> {
  static const _bannerHeight = 130.0;
  static const _cardRadius = 15.0;
  static const _contentLeftPadding = 24.0;
  static const _contentTopPadding = 20.0;
  static const _contentBottomPadding = 20.0;
  static const _titleMaxWidth = 320.0;
  static const _bodyTextMaxWidth = 228.0;
  static const _duckWidth = 88.0;
  static const _duckTextReservedWidth = 91.0;
  static const _closeTextReservedWidth = 24.0;
  static const _duckRightInset = 20.0;
  static const _closeTopInset = 14.0;
  static const _closeRightInset = 18.0;
  static const _ctaIconGap = 4.0;
  static const _maxTextScaleFactor = 1.3;
  bool _dismissed = false;

  @override
  Widget build(BuildContext context) {
    if (_dismissed) return const SizedBox.shrink();
    if (localSettings.isLocalGallerySettingsBannerDismissed) {
      return const SizedBox.shrink();
    }

    final l10n = context.strings;
    final colors = context.componentColors;
    final textDirection = Directionality.of(context);

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: _maxTextScaleFactor,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final titleWidth = math
              .min(
                _titleMaxWidth,
                constraints.maxWidth -
                    _contentLeftPadding -
                    _closeTextReservedWidth,
              )
              .clamp(120.0, _titleMaxWidth);
          final bodyTextWidth = math
              .min(
                _bodyTextMaxWidth,
                constraints.maxWidth -
                    _contentLeftPadding -
                    _duckTextReservedWidth,
              )
              .clamp(120.0, _bodyTextMaxWidth);

          return GestureDetector(
            onTap: widget.onGetStarted,
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(minHeight: _bannerHeight),
              clipBehavior: Clip.hardEdge,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(_cardRadius),
                color: const Color(0xFF292929),
              ),
              child: Stack(
                children: [
                  Positioned(
                    right: _duckRightInset,
                    bottom: 0,
                    child: IgnorePointer(
                      child: Image.asset(
                        "assets/ducky_settings.png",
                        width: _duckWidth,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      _contentLeftPadding,
                      _contentTopPadding,
                      24,
                      _contentBottomPadding,
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        minHeight:
                            _bannerHeight -
                            _contentTopPadding -
                            _contentBottomPadding,
                      ),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: titleWidth),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.offlineSettingsBannerTitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyles.display3.copyWith(
                                  color: Colors.white,
                                  fontSize: 18,
                                  height: 1,
                                ),
                              ),
                              const SizedBox(height: 8),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: bodyTextWidth,
                                ),
                                child: Text(
                                  l10n.offlineSettingsBannerDesc,
                                  style: TextStyles.mini.copyWith(
                                    color: Colors.white.withValues(alpha: 0.79),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: bodyTextWidth,
                                ),
                                child: GestureDetector(
                                  onTap: widget.onGetStarted,
                                  behavior: HitTestBehavior.opaque,
                                  child: FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: AlignmentDirectional.centerStart,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          l10n.getStarted,
                                          style: TextStyles.body.copyWith(
                                            color: colors.primary,
                                          ),
                                        ),
                                        const SizedBox(width: _ctaIconGap),
                                        Text(
                                          textDirection == TextDirection.rtl
                                              ? "\u2190"
                                              : "\u2192",
                                          style: TextStyles.body.copyWith(
                                            color: colors.primary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    top: _closeTopInset,
                    right: _closeRightInset,
                    child: IconButtonComponent(
                      tooltip: l10n.close,
                      size: 28,
                      iconSize: IconSizes.tiny,
                      variant: IconButtonComponentVariant.unfilled,
                      shouldSurfaceExecutionStates: false,
                      onTap: _onDismiss,
                      icon: const HugeIcon(
                        icon: HugeIcons.strokeRoundedCancel01,
                        color: Colors.white,
                        size: IconSizes.tiny,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _onDismiss() {
    setState(() {
      _dismissed = true;
    });
    unawaited(localSettings.setLocalGallerySettingsBannerDismissed(true));
  }
}
