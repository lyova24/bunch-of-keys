"""Validate a decoded Apple profile and prepare the app's private Keychain group."""
import datetime
import plistlib
import sys


def entitlements(profile, bundle_id):
    if profile.get("ExpirationDate", datetime.datetime.min) <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
        raise ValueError("The Touch ID provisioning profile has expired.")
    permissions = profile.get("Entitlements", {})
    team = permissions.get("com.apple.developer.team-identifier", "")
    application = f"{team}.{bundle_id}"
    if not team or permissions.get("com.apple.application-identifier") != application:
        raise ValueError("Use an explicit macOS profile for this Team ID and bundle identifier.")
    groups = permissions.get("keychain-access-groups", [])
    if application not in groups and f"{team}.*" not in groups:
        raise ValueError("The profile must authorize the app's private Keychain access group.")
    return {
        "com.apple.application-identifier": application,
        "com.apple.developer.team-identifier": team,
        "keychain-access-groups": [application],
    }


if __name__ == "__main__":
    try:
        with open(sys.argv[1], "rb") as source:
            result = entitlements(plistlib.load(source), sys.argv[2])
        with open(sys.argv[3], "wb") as destination:
            plistlib.dump(result, destination)
    except (ValueError, KeyError) as error:
        sys.exit(str(error))
