import 'package:hiddify/features/nimbus/auth/model/nimbus_auth_models.dart';

enum NimbusRoutePreferenceDecision { create, duplicate, switchType, limitReached }

class NimbusRoutePreferenceResolution {
  const NimbusRoutePreferenceResolution(this.decision, {this.existing});

  final NimbusRoutePreferenceDecision decision;
  final NimbusRoutePreference? existing;
}

NimbusRoutePreferenceResolution resolveNimbusRoutePreference({
  required Iterable<NimbusRoutePreference> items,
  required int limit,
  required String domain,
  required String requestedType,
}) {
  NimbusRoutePreference? existing;
  for (final item in items) {
    if (item.value == domain) {
      existing = item;
      break;
    }
  }

  if (existing != null) {
    return NimbusRoutePreferenceResolution(
      existing.type == requestedType
          ? NimbusRoutePreferenceDecision.duplicate
          : NimbusRoutePreferenceDecision.switchType,
      existing: existing,
    );
  }
  if (limit > 0 && items.length >= limit) {
    return const NimbusRoutePreferenceResolution(NimbusRoutePreferenceDecision.limitReached);
  }
  return const NimbusRoutePreferenceResolution(NimbusRoutePreferenceDecision.create);
}
