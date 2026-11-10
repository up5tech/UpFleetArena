import '../shared/models/room_models.dart';
import 'generated/app_localizations.dart';

/// The localized name of a fleet preset.
///
/// [FleetPreset.label] is the wire-facing English name; the UI must use this
/// extension so the Vietnamese build does not mix "Standard" into its copy.
extension FleetPresetLabel on FleetPreset {
  String localizedLabel(AppLocalizations l10n) => switch (this) {
    FleetPreset.small => l10n.fleetPresetSmall,
    FleetPreset.standard => l10n.fleetPresetStandard,
    FleetPreset.large => l10n.fleetPresetLarge,
  };
}
