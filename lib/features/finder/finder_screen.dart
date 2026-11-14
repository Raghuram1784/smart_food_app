import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/motion.dart';
import '../commerce/commerce_widgets.dart';
import '../location/delivery_destination.dart';
import 'finder_controller.dart';
import 'finder_models.dart';
import 'finder_theme.dart';
import 'recommendation_card.dart';

const starterPrompts = ['Chicken Biryani under ₹150', 'Veg food under ₹200', 'High-protein meals', 'Spicy snacks under ₹100'];

/// Smart Food Finder: a chat where Gemini understands the request and the
/// backend catalog + pricing engine produce every dish, fee and total shown.
class FinderScreen extends ConsumerStatefulWidget {
  final String? initialPrompt;
  const FinderScreen({super.key, this.initialPrompt});
  @override
  ConsumerState<FinderScreen> createState() => _FinderScreenState();
}

class _FinderScreenState extends ConsumerState<FinderScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final focus = FocusNode();

  @override
  void initState() {
    super.initState();
    final prompt = widget.initialPrompt?.trim();
    if (prompt != null && prompt.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.read(finderControllerProvider.notifier).send(prompt);
      });
    }
  }

  @override
  void dispose() {
    input.dispose();
    scroll.dispose();
    focus.dispose();
    super.dispose();
  }

  void _send([String? text]) {
    final t = (text ?? input.text).trim();
    if (t.isEmpty) return;
    if (text == null) input.clear();
    ref.read(finderControllerProvider.notifier).send(t);
  }

  void _toBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !scroll.hasClients) return;
        scroll.animateTo(scroll.position.maxScrollExtent, duration: motionDuration(context, 280), curve: Curves.easeOutCubic);
      });

  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final state = ref.watch(finderControllerProvider);
    final area = ref.watch(deliveryServiceAreaProvider)?.id ?? state.chosenAreaId;
    ref.listen(finderControllerProvider, (prev, next) {
      if (prev?.messages.length != next.messages.length || prev?.busy != next.busy) _toBottom();
    });
    final lastAssistant = state.messages.lastIndexWhere((m) => m is AssistantFinderMessage);
    return Scaffold(
      backgroundColor: c.ivory,
      resizeToAvoidBottomInset: true,
      body: Column(children: [
        _Header(onReset: state.messages.isEmpty ? null : () => ref.read(finderControllerProvider.notifier).reset()),
        Expanded(
          child: GestureDetector(
            onTap: () => focus.unfocus(),
            behavior: HitTestBehavior.translucent,
            child: state.messages.isEmpty
                ? _Welcome(onPrompt: _send)
                : ListView.builder(
                    key: const ValueKey('finder-list'),
                    controller: scroll,
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    itemCount: state.messages.length + (state.busy ? 1 : 0),
                    itemBuilder: (context, i) {
                      if (i == state.messages.length) return const _Thinking();
                      final m = state.messages[i];
                      return _FadeIn(
                        key: ValueKey('msg-$i'),
                        child: switch (m) {
                          UserFinderMessage(:final text) => _UserBubble(text),
                          AssistantFinderMessage(:final reply) => _AssistantTurn(reply: reply, area: area, isLatest: i == lastAssistant && !state.busy, onPrompt: _send, messageIndex: i),
                          NoteFinderMessage() => _Note(m, onRetry: m.retryText == null ? null : () => ref.read(finderControllerProvider.notifier).send(m.retryText!, isRetry: true)),
                        },
                      );
                    },
                  ),
          ),
        ),
        _Composer(controller: input, focus: focus, busy: state.busy, onSend: _send),
      ]),
    );
  }
}

class _Header extends StatelessWidget {
  final VoidCallback? onReset;
  const _Header({this.onReset});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      color: c.forest,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(24))),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(4, 6, 8, 14),
          child: IconTheme(
            data: IconThemeData(color: c.onForest),
            child: Row(children: [
              IconButton(
                tooltip: 'Back',
                onPressed: () => context.canPop() ? context.pop() : context.go('/'),
                icon: const Icon(Icons.arrow_back),
              ),
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: c.gold, shape: BoxShape.circle),
                child: Icon(Icons.auto_awesome, color: c.forest, size: 22),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Smart Food Finder', maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleLarge?.copyWith(color: c.onForest, fontSize: 21)),
                  Text('Your budget, taste and nutrition goals', maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: c.onForest.withValues(alpha: .8))),
                ]),
              ),
              if (onReset != null) IconButton(key: const ValueKey('finder-reset'), tooltip: 'New search', onPressed: onReset, icon: const Icon(Icons.restart_alt)),
              const CartShortcut(),
            ]),
          ),
        ),
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  final ValueChanged<String> onPrompt;
  const _Welcome({required this.onPrompt});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    return ListView(padding: const EdgeInsets.fromLTRB(20, 28, 20, 24), children: [
      Center(
        child: Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(color: c.paleGreen, shape: BoxShape.circle),
          child: Icon(Icons.ramen_dining_outlined, size: 36, color: c.forest),
        ),
      ),
      const SizedBox(height: 16),
      Text('Tell us what you\'re craving', textAlign: TextAlign.center, style: text.headlineMedium?.copyWith(color: c.charcoal)),
      const SizedBox(height: 8),
      Text(
        'Your budget, taste and nutrition goals. We\'ll find a meal that fits — with the real total, including delivery and fees.',
        textAlign: TextAlign.center,
        style: text.bodyLarge?.copyWith(color: c.muted),
      ),
      const SizedBox(height: 24),
      Text('Try asking', style: text.labelLarge?.copyWith(color: c.muted)),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        for (final p in starterPrompts) _PromptChip(label: p, onTap: () => onPrompt(p)),
      ]),
      const SizedBox(height: 24),
      _InfoRow(icon: Icons.receipt_long_outlined, text: 'Budgets are the total you pay: food, packaging, delivery, fees and taxes.'),
      _InfoRow(icon: Icons.eco_outlined, text: 'Nutrition is shown only where we have data, and is marked as an estimate.'),
      _InfoRow(icon: Icons.lock_outline, text: 'Nothing is ordered until you check out from your cart.'),
    ]);
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoRow({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 18, color: c.forest),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.muted))),
      ]),
    );
  }
}

class _PromptChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final IconData icon;
  const _PromptChip({required this.label, required this.onTap, this.icon = Icons.north_east});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    return ActionChip(
      key: ValueKey('prompt-$label'),
      onPressed: onTap,
      avatar: Icon(icon, size: 16, color: c.forest),
      label: Text(label),
      backgroundColor: c.paleGreen,
      side: BorderSide(color: c.forest.withValues(alpha: .15)),
      labelStyle: Theme.of(context).textTheme.labelLarge?.copyWith(color: c.forest),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    );
  }
}

class _UserBubble extends StatelessWidget {
  final String text;
  const _UserBubble(this.text);
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.only(left: 48, bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: c.forest,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(18), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(4)),
        ),
        child: Text(text, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: c.onForest)),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar();
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(color: c.forest, shape: BoxShape.circle),
      child: Icon(Icons.auto_awesome, size: 16, color: c.gold),
    );
  }
}

class _AssistantTurn extends ConsumerWidget {
  final FinderReply reply;
  final String? area;
  final bool isLatest;
  final int messageIndex;
  final ValueChanged<String> onPrompt;
  const _AssistantTurn({required this.reply, required this.area, required this.isLatest, required this.onPrompt, this.messageIndex = 0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    final r = reply.result;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Avatar(),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.card,
                border: Border.all(color: c.outline),
                borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(18), bottomLeft: Radius.circular(18), bottomRight: Radius.circular(18)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (reply.intentSummary != null && reply.status != 'NEEDS_CLARIFICATION')
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: c.paleGreen, borderRadius: BorderRadius.circular(999)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        child: Text(
                          'Your request: ${reply.intentSummary}${r?.budgetPaise != null ? ' · ${rupees(r!.budgetPaise!)} total' : ''}',
                          style: text.labelMedium?.copyWith(color: c.forest, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ),
                Text(reply.reply, key: const ValueKey('finder-reply'), style: text.bodyLarge?.copyWith(color: c.charcoal)),
                if (reply.aiNotice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Icon(Icons.info_outline, size: 14, color: c.muted),
                      const SizedBox(width: 6),
                      Expanded(child: Text(reply.aiNotice!, key: const ValueKey('finder-ai-notice'), style: text.bodySmall?.copyWith(color: c.muted))),
                    ]),
                  ),
                if (reply.status == 'NEEDS_AREA' && reply.areas.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    for (final a in reply.areas)
                      _PromptChip(label: a.name.split(',').first, icon: Icons.place_outlined, onTap: () => ref.read(finderControllerProvider.notifier).chooseArea(a)),
                  ]),
                ],
              ]),
            ),
          ),
        ]),
        if (reply.selected case final s?) ...[
          const SizedBox(height: 12),
          RecommendationCard(rec: s, area: area, index: 0, autoAdd: isLatest && ref.read(finderControllerProvider.notifier).claimAutoAdd('${reply.conversationId}:$messageIndex')),
        ],
        if (r != null) ..._results(context, r),
        if (isLatest && (reply.status == 'RESULTS' || reply.status == 'SELECTED')) ...[
          const SizedBox(height: 12),
          _Refinements(result: r, onPrompt: onPrompt),
        ],
        if (isLatest && reply.status == 'NEEDS_CLARIFICATION') ...[
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final p in starterPrompts) _PromptChip(label: p, onTap: () => onPrompt(p))]),
        ],
      ]),
    );
  }

  List<Widget> _results(BuildContext context, FinderResult r) {
    final c = FinderColors.of(context);
    var index = 0;
    List<Widget> cards(List<FinderRecommendation> list) => [
          for (final rec in list) ...[
            const SizedBox(height: 10),
            RecommendationCard(rec: rec, area: area, index: ++index),
          ],
        ];
    return [
      if (r.exact.isNotEmpty) ...[
        _SectionHeader(
          key: const ValueKey('section-exact'),
          icon: Icons.verified_outlined,
          title: r.budgetPaise != null ? 'Within your ${rupees(r.budgetPaise!)} budget' : 'Best matches',
          subtitle: 'Totals include delivery, packaging and fees for ${r.areaName.split(',').first}.',
          fg: c.success,
          bg: c.successBg,
        ),
        ...cards(r.exact),
      ],
      if (r.similar.isNotEmpty) ...[
        _SectionHeader(
          key: const ValueKey('section-similar'),
          icon: Icons.auto_awesome,
          title: r.exact.isEmpty ? 'Similar dishes that fit' : 'You may also like',
          subtitle: 'Chosen for a similar taste${r.budgetPaise != null ? ' and your budget' : ''}.',
          fg: c.charcoal,
          bg: c.goldBg,
        ),
        ...cards(r.similar),
      ],
      if (r.nearBudget.isNotEmpty) ...[
        _SectionHeader(
          key: const ValueKey('section-near'),
          icon: Icons.north_east,
          title: 'Slightly above your budget',
          subtitle: 'Suggestions only — we\'ll ask before adding any of these.',
          fg: c.warn,
          bg: c.warnBg,
        ),
        ...cards(r.nearBudget),
      ],
      // No separate empty-state card: the reply already explains, and refinement chips follow.
      if (r.notice.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 10, left: 4, right: 4),
          child: Text(r.notice, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.muted)),
        ),
    ];
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final Color fg, bg;
  const _SectionHeader({super.key, required this.icon, required this.title, required this.subtitle, required this.fg, required this.bg});
  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(icon, color: fg, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: text.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w800)),
              Text(subtitle, style: text.bodySmall?.copyWith(color: fg.withValues(alpha: .85))),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Refinements extends StatelessWidget {
  final FinderResult? result;
  final ValueChanged<String> onPrompt;
  const _Refinements({required this.result, required this.onPrompt});
  @override
  Widget build(BuildContext context) {
    final hasBudget = result?.budgetPaise != null;
    final options = <(String, IconData)>[
      if ((result?.exact.isNotEmpty ?? false) || (result?.similar.isNotEmpty ?? false)) ('Show cheaper options', Icons.savings_outlined),
      ('Make it spicier', Icons.whatshot_outlined),
      ('Less spicy', Icons.water_drop_outlined),
      ('Vegetarian instead', Icons.eco_outlined),
      ('High protein', Icons.fitness_center_outlined),
      if (hasBudget) ('Remove the budget', Icons.money_off_outlined),
      if (result != null && result!.exact.isEmpty && hasBudget) ('Increase budget to ${rupees(((result!.budgetPaise! * 1.25) / 1000).ceil() * 1000)}', Icons.trending_up),
    ];
    return SingleChildScrollView(
      key: const ValueKey('finder-refinements'),
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final (label, icon) in options) Padding(padding: const EdgeInsets.only(right: 8), child: _PromptChip(label: label, icon: icon, onTap: () => onPrompt(label))),
      ]),
    );
  }
}

class _Note extends StatelessWidget {
  final NoteFinderMessage note;
  final VoidCallback? onRetry;
  const _Note(this.note, {this.onRetry});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final fg = note.isError ? c.warn : c.muted;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        key: ValueKey(note.isError ? 'finder-error' : 'finder-note'),
        padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
        decoration: BoxDecoration(color: note.isError ? c.warnBg : c.paleGreen, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Icon(note.isError ? Icons.error_outline : Icons.info_outline, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(child: Text(note.text, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: fg))),
          if (onRetry != null) TextButton(onPressed: onRetry, child: const Text('Retry')),
        ]),
      ),
    );
  }
}

class _Thinking extends StatelessWidget {
  const _Thinking();
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    Widget bar(double w) => Container(height: 10, width: w, margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: c.outline, borderRadius: BorderRadius.circular(6)));
    return Column(key: const ValueKey('finder-thinking'), crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const _Avatar(),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.outline)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: c.forest)),
            const SizedBox(width: 10),
            Text('Checking menus and prices…', style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: c.muted)),
          ]),
        ),
      ]),
      const SizedBox(height: 12),
      // Skeleton of a result card while the search runs.
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: c.card, borderRadius: BorderRadius.circular(20), border: Border.all(color: c.outline)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(width: 92, height: 92, decoration: BoxDecoration(color: c.outline, borderRadius: BorderRadius.circular(14))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [bar(90), bar(160), bar(120), bar(70)])),
        ]),
      ),
    ]);
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focus;
  final bool busy;
  final void Function([String?]) onSend;
  const _Composer({required this.controller, required this.focus, required this.busy, required this.onSend});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    return Material(
      color: c.card,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(border: Border(top: BorderSide(color: c.outline))),
          padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
          child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Expanded(
              child: TextField(
                key: const ValueKey('finder-input'),
                controller: controller,
                focusNode: focus,
                minLines: 1,
                maxLines: 4,
                maxLength: 500,
                textInputAction: TextInputAction.send,
                textCapitalization: TextCapitalization.sentences,
                onSubmitted: busy ? null : (_) => onSend(),
                decoration: InputDecoration(
                  hintText: 'Ask for food, a budget or a taste…',
                  counterText: '',
                  filled: true,
                  fillColor: c.ivory,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: c.outline)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: c.outline)),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide(color: c.forest, width: 1.5)),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              key: const ValueKey('finder-send'),
              tooltip: 'Send',
              onPressed: busy ? null : () => onSend(),
              style: IconButton.styleFrom(backgroundColor: c.forest, foregroundColor: c.onForest, minimumSize: const Size(48, 48)),
              icon: const Icon(Icons.send_rounded),
            ),
          ]),
        ),
      ),
    );
  }
}

class _FadeIn extends StatelessWidget {
  final Widget child;
  const _FadeIn({super.key, required this.child});
  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: motionDuration(context, 260),
        curve: Curves.easeOutCubic,
        builder: (context, t, child) => Opacity(opacity: t, child: Transform.translate(offset: Offset(0, (1 - t) * 8), child: child)),
        child: child,
      );
}

/// Compact Home entry point for the finder (an integrated row, not a banner).
class FinderEntryCard extends StatelessWidget {
  const FinderEntryCard({super.key});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      color: c.paleGreen,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.forest.withValues(alpha: .12))),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('finder-entry'),
        onTap: () => context.push('/finder'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: c.forest, shape: BoxShape.circle),
              child: Icon(Icons.auto_awesome, size: 20, color: c.gold),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Find food with AI', style: text.titleSmall?.copyWith(color: c.forest, fontWeight: FontWeight.w800)),
                Text('Search by budget, taste and nutrition', maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: c.muted)),
              ]),
            ),
            Icon(Icons.chevron_right, color: c.forest),
          ]),
        ),
      ),
    );
  }
}
