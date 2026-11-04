import ManagedSettings
import ManagedSettingsUI
import UIKit

/// Stub shield for the Family Controls entitlement.
/// Version 1 should read the reset time from the App Group. This file does not
/// read the feed, the account, or any post.
class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        enoughShield()
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        enoughShield()
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        enoughShield()
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        enoughShield()
    }

    private func enoughShield() -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundBlurStyle: .systemMaterial,
            backgroundColor: .systemBackground,
            icon: nil,
            title: ShieldConfiguration.Label(text: "You're done for today", color: .label),
            subtitle: ShieldConfiguration.Label(
                text: "Enough will open the feed again at your reset time.",
                color: .secondaryLabel
            ),
            primaryButtonLabel: ShieldConfiguration.Label(text: "OK", color: .label),
            primaryButtonBackgroundColor: .secondarySystemFill,
            secondaryButtonLabel: nil
        )
    }
}
