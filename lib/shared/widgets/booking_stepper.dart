import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_typography.dart';
import '../../core/theme/app_decorations.dart';
import 'app_button.dart';
import 'sticky_action_bar.dart';

/// One page of a [BookingStepper].
class BookingStep {
  final String title;
  final List<Widget> children;
  const BookingStep(this.title, this.children);
}

/// A booking form one step at a time — Where → … → Payment → Confirm — with
/// the fare always in view at the top (web twin: setupFormSteps in
/// js/customer.js). Each step has its own [Form], so Next only checks the
/// fields on screen; the finish button checks them all again first.
///
/// With [summary] the stepper adds its own Confirm step listing those rows.
/// Without it the Confirm step is the next screen (the ride's
/// BookingConfirmationScreen), so a "Confirm" dot shows but is never current.
class BookingStepper extends StatefulWidget {
  final List<BookingStep> steps;
  final String fare;
  final String finishLabel;
  final VoidCallback? onFinish;
  final bool finishLoading;
  final VoidCallback? onChanged;
  final List<(String, String)> Function()? summary;

  const BookingStepper({
    super.key,
    required this.steps,
    required this.fare,
    required this.finishLabel,
    required this.onFinish,
    this.finishLoading = false,
    this.onChanged,
    this.summary,
  });

  @override
  State<BookingStepper> createState() => _BookingStepperState();
}

class _BookingStepperState extends State<BookingStepper> {
  late final List<GlobalKey<FormState>> _formKeys =
      List.generate(widget.steps.length, (_) => GlobalKey<FormState>());
  final _scroll = ScrollController();
  int _current = 0;

  bool get _hasConfirmStep => widget.summary != null;
  int get _lastIndex => widget.steps.length - (_hasConfirmStep ? 0 : 1);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _go(int i) {
    FocusScope.of(context).unfocus();
    setState(() => _current = i.clamp(0, _lastIndex));
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _next() {
    if (_formKeys[_current].currentState?.validate() ?? true) _go(_current + 1);
  }

  void _finish() {
    for (var i = 0; i < _formKeys.length; i++) {
      if (!(_formKeys[i].currentState?.validate() ?? true)) {
        _go(i);
        // Re-run on the now-visible step so its errors show.
        WidgetsBinding.instance.addPostFrameCallback((_) => _formKeys[i].currentState?.validate());
        return;
      }
    }
    widget.onFinish?.call();
  }

  @override
  Widget build(BuildContext context) {
    final titles = [...widget.steps.map((s) => s.title), 'Confirm'];
    final onLast = _current == _lastIndex;
    final onConfirm = _hasConfirmStep && _current == widget.steps.length;

    return PopScope(
      canPop: _current == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(_current - 1);
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: BookingStepsHeader(titles: titles, current: _current, fare: widget.fare),
          ),
          Expanded(
            child: SingleChildScrollView(
              controller: _scroll,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < widget.steps.length; i++)
                    Offstage(
                      offstage: i != _current,
                      child: TickerMode(
                        enabled: i == _current,
                        child: Form(
                          key: _formKeys[i],
                          onChanged: widget.onChanged,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: widget.steps[i].children,
                          ),
                        ),
                      ),
                    ),
                  if (onConfirm) _Summary(rows: widget.summary!()),
                ],
              ),
            ),
          ),
          StickyActionBar(
            child: Row(
              children: [
                if (_current > 0) ...[
                  Expanded(
                    child: AppButton(
                      text: 'Back',
                      type: AppButtonType.outline,
                      onPressed: () => _go(_current - 1),
                    ),
                  ),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  flex: 2,
                  child: AppButton(
                    text: onLast ? widget.finishLabel : 'Next',
                    isLoading: onLast && widget.finishLoading,
                    onPressed: onLast ? (widget.onFinish == null ? null : _finish) : _next,
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

/// Numbered step dots plus the fare, as on the web's .form-steps-bar.
class BookingStepsHeader extends StatelessWidget {
  final List<String> titles;
  final int current;
  final String fare;

  const BookingStepsHeader({super.key, required this.titles, required this.current, required this.fare});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: AppDecorations.softCard(borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          for (var i = 0; i < titles.length; i++)
            Expanded(child: _StepDot(index: i, title: titles[i], current: current)),
          Container(
            width: 1,
            height: 34,
            margin: const EdgeInsets.symmetric(horizontal: 10),
            color: AppColors.divider,
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Fare', style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600)),
              Text(fare, style: AppTypography.bodyBold.copyWith(fontSize: 16)),
            ],
          ),
        ],
      ),
    );
  }
}

class _StepDot extends StatelessWidget {
  final int index;
  final String title;
  final int current;

  const _StepDot({required this.index, required this.title, required this.current});

  @override
  Widget build(BuildContext context) {
    final done = index < current;
    final now = index == current;
    final ink = now ? AppColors.primaryDark : AppColors.neutral500;
    return Semantics(
      label: 'Step ${index + 1}, $title${now ? ', current' : done ? ', done' : ''}',
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 24,
            height: 24,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: now ? AppColors.primary : done ? AppColors.primary50 : AppColors.neutral100,
              border: Border.all(color: now || done ? AppColors.primary : AppColors.neutral300, width: 1.5),
            ),
            child: done
                ? FaIcon(FontAwesomeIcons.check, size: 11, color: AppColors.primaryDark)
                : Text('${index + 1}',
                    style: AppTypography.caption.copyWith(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: now ? Colors.white : AppColors.neutral500,
                    )),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              title,
              maxLines: 1,
              style: AppTypography.caption.copyWith(fontSize: 11, fontWeight: FontWeight.w600, color: ink),
            ),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  final List<(String, String)> rows;
  const _Summary({required this.rows});

  @override
  Widget build(BuildContext context) {
    final shown = rows.where((r) => r.$2.trim().isNotEmpty).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Check your booking', style: AppTypography.h3),
        const SizedBox(height: 12),
        Container(
          decoration: AppDecorations.softCard(borderRadius: BorderRadius.circular(14)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var i = 0; i < shown.length; i++)
                Container(
                  color: i == shown.length - 1 ? AppColors.primary50 : null,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(shown[i].$1, style: AppTypography.body.copyWith(color: AppColors.neutral500, fontSize: 14)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(shown[i].$2,
                            textAlign: TextAlign.right,
                            style: AppTypography.bodyBold.copyWith(fontSize: 14)),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
