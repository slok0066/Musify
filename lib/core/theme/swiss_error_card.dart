import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'swiss_tokens.dart';

/// The global `ErrorWidget.builder` replacement (PRD Law 4).
///
/// Flutter's default is the red screen of death in debug and a grey box in
/// release. Musify renders a Swiss instrument-panel fault card instead: it names
/// the fault in monospace, offers the exception text, and gives the user a way
/// *forward* rather than a dead end.
///
/// It is written to be dependency-free (no `MediaQuery`, no `Directionality`,
/// no `Theme` requirement) because it can be built from anywhere in the tree,
/// including before `MaterialApp` exists.
class SwissErrorCard extends StatelessWidget {
  const SwissErrorCard({required this.details, super.key});

  /// Extra diagnostic lines appended to `COPY REPORT`.
  ///
  /// Set once at startup by `main()`, so this card can stay free of any import
  /// that might itself be the thing that failed.
  static String Function()? reportExtra;

  final FlutterErrorDetails details;

  String get _summary {
    final exception = details.exceptionAsString();
    final firstLine = exception.split('\n').first.trim();
    return firstLine.length > 220
        ? '${firstLine.substring(0, 220)}…'
        : firstLine;
  }

  String get _report {
    final buffer = StringBuffer()
      ..writeln('MUSIFY FAULT REPORT')
      ..writeln('---')
      ..writeln('EXCEPTION: ${details.exceptionAsString()}')
      ..writeln('LIBRARY: ${details.library ?? 'unknown'}');
    if (details.context != null) buffer.writeln('CONTEXT: ${details.context}');

    final extra = reportExtra;
    if (extra != null) {
      buffer.writeln('---');
      try {
        buffer.writeln(extra());
      } catch (e) {
        buffer.writeln('DIAGNOSTICS UNAVAILABLE: $e');
      }
    }
    final stack = details.stack;
    if (stack != null) {
      buffer
        ..writeln('---')
        ..writeln(stack.toString());
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    const t = SwissTokens.carbon;

    return Directionality(
      textDirection: TextDirection.ltr,
      child: Container(
        color: t.bg,
        padding: const EdgeInsets.all(SwissGrid.gutter),
        alignment: Alignment.center,
        child: SingleChildScrollView(
          child: Container(
            padding: const EdgeInsets.all(SwissGrid.lg),
            decoration: BoxDecoration(
              color: t.surface,
              border: Border.all(color: t.hairlineStrong),
              borderRadius: BorderRadius.circular(SwissTokens.radius),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(width: 7, height: 7, color: t.warning),
                    const SizedBox(width: SwissGrid.sm),
                    Text(
                      'UI FAULT // RECOVERED',
                      style: SwissType.label.copyWith(color: t.warning),
                    ),
                  ],
                ),
                const SizedBox(height: SwissGrid.md),
                Text(
                  'THIS PANEL FAILED TO RENDER',
                  style: SwissType.displaySm.copyWith(color: t.ink),
                ),
                const SizedBox(height: SwissGrid.sm),
                Text(
                  _summary,
                  style:
                      SwissType.mono.copyWith(color: t.inkMuted, fontSize: 11),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: SwissGrid.lg),
                Row(
                  children: [
                    _ErrorKeycap(
                      label: 'DISMISS',
                      onTap: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).maybePop();
                        }
                      },
                    ),
                    const SizedBox(width: SwissGrid.sm),
                    _ErrorKeycap(
                      label: 'COPY REPORT',
                      onTap: () =>
                          Clipboard.setData(ClipboardData(text: _report)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A locally-built keycap: the themed one lives in `tactile_decorations.dart`,
/// but this card must not depend on anything that could itself have failed.
class _ErrorKeycap extends StatelessWidget {
  const _ErrorKeycap({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const t = SwissTokens.carbon;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
            horizontal: SwissGrid.md, vertical: SwissGrid.sm),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [t.keycapTop, t.keycapBottom],
          ),
          border: Border.all(color: t.hairlineStrong),
          borderRadius: BorderRadius.circular(SwissTokens.radius),
        ),
        child: Text(
          label,
          style: SwissType.micro
              .copyWith(color: t.ink, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
