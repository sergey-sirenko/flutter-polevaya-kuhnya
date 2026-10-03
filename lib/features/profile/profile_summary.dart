import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:polevaya_kuhnya/app/strings.dart';
import 'package:polevaya_kuhnya/core/auth/session_controller.dart';
import 'package:polevaya_kuhnya/core/auth/user_profile.dart';
import 'package:polevaya_kuhnya/shared/display_formats.dart';

class ProfileSummary extends ConsumerWidget {
  const ProfileSummary({super.key});

  static String display(String value) =>
      value.trim().isEmpty ? AppStrings.profileValueMissing : value.trim();

  static String _money(Object? value) {
    final n = _amount(value);
    return n != null ? formatRubles(n) : AppStrings.profileValueMissing;
  }

  static String _percent(Object? value) {
    final n = value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
    if (n <= 0) return AppStrings.profileValueMissing;
    final asInt = n.round();
    return n == asInt ? '$asInt %' : '$n %';
  }

  static bool _promotion(Object? value) {
    if (value == true || value == 1) return true;
    return value?.toString() == '1';
  }

  static num? _amount(Object? value) {
    final n = value is num ? value : num.tryParse('$value');
    if (n == null || !n.isFinite || n <= 0) return null;
    return n;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(sessionProfileProvider);
    if (profile == null) {
      return const SizedBox.shrink();
    }
    final user = profile.rawUser;
    final limit = _amount(user['Limit']);
    final theme = Theme.of(context).textTheme;
    final identity = [
      _shownRow(AppStrings.profileFullName, display(profile.employee)),
      _shownRow(AppStrings.profileOrganization, display(profile.name)),
      _shownRow(AppStrings.profileLogin, display(profile.login)),
      _shownRow(AppStrings.profilePhone, display(profile.phone)),
    ].whereType<Widget>();
    final conditions = [
      _shownRow(
        AppStrings.profileDiscountPercent,
        _percent(user['DiscountPercentage']),
      ),
      _shownRow(AppStrings.profileDiscountDay, _money(user['DiscountClient'])),
      _shownRow(
        AppStrings.profileDiscountPromotion,
        _promotion(user['DiscountPromotion'])
            ? AppStrings.profileDiscountPromotionOn
            : AppStrings.profileDiscountPromotionOff,
      ),
      _shownRow(
        AppStrings.profileMinimumPayment,
        _money(user['MinimumPaymentAmount'] ?? user['MinimumPaymentАmount']),
      ),
      _shownRow(
        AppStrings.profileMinimumOrder,
        _money(user['MinimumOrderAmount']),
      ),
      _shownRow(
        AppStrings.profileLimit,
        limit == null ? AppStrings.profileLimitNone : formatRubles(limit),
      ),
      _shownRow(
        AppStrings.profileLimitPeriod,
        limit == null
            ? AppStrings.profileLimitNone
            : display(user['LimitPeriod']?.toString() ?? ''),
      ),
    ].whereType<Widget>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ...identity,
        if (conditions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(AppStrings.profileConditions, style: theme.titleMedium),
          const SizedBox(height: 8),
          ...conditions,
        ],
      ],
    );
  }

  static const _hiddenValues = {
    AppStrings.profileValueMissing,
    AppStrings.profileLimitNone,
    AppStrings.profileDiscountPromotionOff,
  };

  Widget? _shownRow(String label, String value) {
    if (_hiddenValues.contains(value)) return null;
    return _row(label, value);
  }

  Widget _row(String label, String value) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked =
            constraints.maxWidth < 360 ||
            MediaQuery.textScalerOf(context).scale(16) >= 20.8;
        final labelWidget = Text(
          label,
          style: Theme.of(context).textTheme.bodySmall
              ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
        );
        final valueWidget = Text(
          value,
          style: Theme.of(context).textTheme.titleSmall,
          textAlign: stacked ? TextAlign.start : TextAlign.end,
          key: ValueKey('profile-field-$label'),
        );
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: stacked
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    labelWidget,
                    const SizedBox(height: 4),
                    valueWidget,
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: labelWidget),
                    const SizedBox(width: 12),
                    Expanded(child: valueWidget),
                  ],
                ),
        );
      },
    );
  }
}

extension ProfileSummaryFields on UserProfile {
  String get organizationLabel => ProfileSummary.display(name);
  String get fullNameLabel => ProfileSummary.display(employee);
}
