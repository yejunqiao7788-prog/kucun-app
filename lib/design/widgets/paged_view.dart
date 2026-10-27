import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../state/app_state.dart';
import '../../state/list_controller.dart';
import '../tokens.dart';
import 'state_views.dart';
import 'surfaces.dart';

/// 列表页统一外壳：下拉刷新 + 触底翻页 + 断网横幅 + 空/错状态。
/// 所有分页模块共用同一套交互，用户学一次就会。
class PagedView<T> extends StatefulWidget {
  const PagedView({
    super.key,
    required this.controller,
    required this.itemBuilder,
    required this.emptyTitle,
    this.emptyHint,
    this.emptyIcon = Icons.inbox_rounded,
    this.emptyAction,
    this.accent,
    this.headerSlivers = const <Widget>[],
    this.padding = const EdgeInsets.fromLTRB(Space.gutter, 4, Space.gutter, 120),
    this.separatorHeight = 10,
    this.onRetry,
  });

  final ListController<T> controller;
  final Widget Function(BuildContext context, T row, int index) itemBuilder;
  final String emptyTitle;
  final String? emptyHint;
  final IconData emptyIcon;
  final Widget? emptyAction;
  final Color? accent;
  final List<Widget> headerSlivers;
  final EdgeInsets padding;
  final double separatorHeight;
  final VoidCallback? onRetry;

  @override
  State<PagedView<T>> createState() => _PagedViewState<T>();
}

class _PagedViewState<T> extends State<PagedView<T>> {
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    _scroll.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant PagedView<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onChanged);
      widget.controller.addListener(_onChanged);
    }
  }

  void _onChanged() => setState(() {});

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final ScrollPosition position = _scroll.position;
    if (position.pixels > position.maxScrollExtent - 320) {
      widget.controller.loadMore();
    }
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    widget.controller.removeListener(_onChanged);
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final L10n l10n = L10n.of(Localizations.localeOf(context));
    final AppState app = AppState.of(context);
    final ListController<T> controller = widget.controller;

    final List<Widget> banners = <Widget>[
      if (!app.online)
        NoticeBanner(text: l10n.commonOfflineBanner, color: AppInk.warning, icon: Icons.wifi_off_rounded),
      if (controller.stale && app.online)
        NoticeBanner(text: l10n.commonStaleBanner, color: AppInk.info, icon: Icons.history_rounded),
      if (app.renewalPending)
        NoticeBanner(text: l10n.commonExpiredBanner, color: AppInk.danger, icon: Icons.lock_outline_rounded),
      if (controller.errorText != null && controller.rows.isNotEmpty)
        NoticeBanner(text: controller.errorText!, color: AppInk.danger, icon: Icons.error_outline_rounded),
    ];

    if (controller.state == LoadState.loading) {
      return const SkeletonList();
    }

    if (controller.state == LoadState.failed && controller.rows.isEmpty) {
      return AppErrorView(
        message: controller.errorText ?? l10n.commonErrorTitle,
        onRetry: widget.onRetry ?? controller.load,
      );
    }

    if (controller.rows.isEmpty && controller.state != LoadState.loading) {
      return AppEmpty(
        title: widget.emptyTitle,
        hint: widget.emptyHint ?? l10n.commonEmptyHint,
        icon: widget.emptyIcon,
        accent: widget.accent,
        action: widget.emptyAction,
      );
    }

    final Widget list = CustomScrollView(
      controller: _scroll,
      slivers: <Widget>[
        ...widget.headerSlivers,
        SliverPadding(
          padding: widget.padding,
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (BuildContext context, int index) => Padding(
                padding: EdgeInsets.only(bottom: widget.separatorHeight),
                child: widget.itemBuilder(context, controller.rows[index], index),
              ),
              childCount: controller.rows.length,
            ),
          ),
        ),
        if (controller.hasMore)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: 32),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              ),
            ),
          )
        else
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );

    return Column(
      children: <Widget>[
        if (banners.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.gutter, 8, Space.gutter, 0),
            child: Column(children: banners),
          ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: controller.refresh,
            color: widget.accent ?? AppInk.dashboard,
            child: list,
          ),
        ),
      ],
    );
  }
}

/// 卡片式一行商品的通用排版，商品/库存/订单列表共用。
class RowCard extends StatelessWidget {
  const RowCard({
    super.key,
    required this.title,
    required this.accent,
    this.subtitle,
    this.trailing,
    this.leading,
    this.onTap,
    this.badges = const <Widget>[],
    this.footRow,
  });

  final String title;
  final Color accent;
  final String? subtitle;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;
  final List<Widget> badges;
  final Widget? footRow;

  @override
  Widget build(BuildContext context) {
    final TextTheme text = Theme.of(context).textTheme;
    return AppCard(
      accent: accent,
      onTap: onTap,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (leading != null) ...<Widget>[leading!, const HGap(10)],
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleMedium),
                    if (subtitle != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(subtitle!,
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall),
                      ),
                  ],
                ),
              ),
              const HGap(8),
              if (trailing != null) trailing!,
            ],
          ),
          if (badges.isNotEmpty) ...<Widget>[
            const VGap(8),
            Wrap(spacing: 6, runSpacing: 6, children: badges),
          ],
          if (footRow != null) ...<Widget>[const VGap(10), footRow!],
        ],
      ),
    );
  }
}

class Thumbnail extends StatelessWidget {
  const Thumbnail({super.key, required this.url, this.size = 46, this.fallbackIcon = Icons.inventory_2_outlined});

  final String? url;
  final double size;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final Widget placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: AppInk.surfaceDim,
        borderRadius: Radii.chip_,
      ),
      child: Icon(fallbackIcon, size: size * 0.45, color: AppInk.textTertiary),
    );
    if (url == null || url!.isEmpty) return placeholder;
    return ClipRRect(
      borderRadius: Radii.chip_,
      child: Image.network(
        url!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        loadingBuilder: (BuildContext context, Widget child, ImageChunkEvent? progress) =>
            progress == null ? child : placeholder,
        errorBuilder: (BuildContext context, Object error, StackTrace? stack) => placeholder,
      ),
    );
  }
}
