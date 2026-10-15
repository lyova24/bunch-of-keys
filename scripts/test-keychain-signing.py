"""Synthetic profile validation: never reads the user's Keychain or profiles."""
import datetime
import importlib.util
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location("signing", Path(__file__).with_name("prepare-keychain-signing.py"))
signing = importlib.util.module_from_spec(spec)
spec.loader.exec_module(signing)


class ProfileTests(unittest.TestCase):
    def profile(self):
        return {
            "ExpirationDate": datetime.datetime.now() + datetime.timedelta(days=1),
            "Entitlements": {
                "com.apple.developer.team-identifier": "TESTTEAM",
                "com.apple.application-identifier": "TESTTEAM.dev.keepy.desktop",
                "keychain-access-groups": ["TESTTEAM.*"],
            },
        }

    def test_private_group_only(self):
        result = signing.entitlements(self.profile(), "dev.keepy.desktop")
        self.assertEqual(result["keychain-access-groups"], ["TESTTEAM.dev.keepy.desktop"])
        self.assertNotIn("com.apple.security.cs.disable-library-validation", result)

    def test_expired_or_wrong_app_or_group_rejected(self):
        expired = self.profile()
        expired["ExpirationDate"] = datetime.datetime(2000, 1, 1)
        wrong_app = self.profile()
        wrong_app["Entitlements"]["com.apple.application-identifier"] = "TESTTEAM.another.app"
        wrong_group = self.profile()
        wrong_group["Entitlements"]["keychain-access-groups"] = ["OTHERTEAM.*"]
        missing_team = self.profile()
        del missing_team["Entitlements"]["com.apple.developer.team-identifier"]
        for profile in (expired, wrong_app, wrong_group, missing_team):
            with self.assertRaises(ValueError):
                signing.entitlements(profile, "dev.keepy.desktop")


if __name__ == "__main__":
    unittest.main()
