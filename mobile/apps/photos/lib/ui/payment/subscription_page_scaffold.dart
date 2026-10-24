import "dart:math" as math;

import "package:ente_components/ente_components.dart";
import "package:ente_strings/ente_strings.dart";
import "package:flutter/material.dart";
import "package:hugeicons/hugeicons.dart";
import "package:photos/ui/account/onboarding_page_scaffold.dart";

class SubscriptionPageScaffold extends StatefulWidget {
  const SubscriptionPageScaffold({
    super.key,
    this.scaffoldKey,
    required this.body,
    required this.onHelpTap,
    this.actions = const [],
    this.isBodyCentered = false,
  });

  final GlobalKey<OnboardingPageScaffoldState>? scaffoldKey;
  final Widget body;
  final VoidCallback onHelpTap;
  final List<Widget> actions;
  final bool isBodyCentered;

  @override
  State<SubscriptionPageScaffold> createState() =>
      _SubscriptionPageScaffoldState();
}

class _SubscriptionPageScaffoldState extends State<SubscriptionPageScaffold> {
  final _footerKey = GlobalKey();
  double _footerHeight = 164;
  bool _measurementScheduled = false;

  void _measureFooter() {
    if (_measurementScheduled) return;
    _measurementScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _measurementScheduled = false;
      if (!mounted) return;
      final height = _footerKey.currentContext?.size?.height;
      if (height != null && (height - _footerHeight).abs() > 0.1) {
        setState(() => _footerHeight = height);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _measureFooter();
    final colors = context.componentColors;
    final bottomInset = math.max(
      Spacing.xxl,
      MediaQuery.paddingOf(context).bottom,
    );
    return NotificationListener<SizeChangedLayoutNotification>(
      onNotification: (_) {
        _measureFooter();
        return false;
      },
      child: Stack(
        children: [
          OnboardingPageScaffold(
            key: widget.scaffoldKey,
            title: context.strings.chooseYourPlan,
            illustration: OnboardingIllustration.pricing,
            headerHeight: 145,
            titleTopPadding: 35,
            bodyHorizontalPadding: Spacing.xxl - 1,
            titleBarStyle: OnboardingTitleBarStyle.header,
            headerTrailing: IconButtonComponent(
              variant: IconButtonComponentVariant.unfilled,
              size: 48,
              iconSize: IconSizes.medium,
              icon: HugeIcon(
                icon: HugeIcons.strokeRoundedHelpCircle,
                color: colors.specialWhite,
              ),
              tooltip: context.strings.faqs,
              onTap: widget.onHelpTap,
            ),
            manageInputFocus: false,
            isBodyCentered: widget.isBodyCentered,
            body: Padding(
              padding: EdgeInsets.only(
                bottom: widget.actions.isEmpty ? Spacing.xxl : _footerHeight,
              ),
              child: widget.body,
            ),
          ),
          if (widget.actions.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 1,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              colors.backgroundBase.withValues(alpha: 0),
                              colors.backgroundBase,
                            ],
                            stops: const [0, 0.73],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizeChangedLayoutNotifier(
                    child: Padding(
                      key: _footerKey,
                      padding: EdgeInsets.fromLTRB(
                        Spacing.lg + MediaQuery.paddingOf(context).left,
                        80,
                        Spacing.lg + MediaQuery.paddingOf(context).right,
                        bottomInset,
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final action in widget.actions)
                            ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 60),
                              child: action,
                            ),
                        ],
                      ),
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
