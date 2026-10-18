import io
import plistlib
import unittest
from zipfile import ZipFile
from catalog import BUNDLE, inspect_ipa, validate


class CatalogTests(unittest.TestCase):
    def ipa(self, **overrides):
        info = {"CFBundleIdentifier": BUNDLE, "CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "2", "MinimumOSVersion": "16.0"}
        info.update(overrides)
        output = io.BytesIO()
        with ZipFile(output, "w") as archive:
            archive.writestr("Payload/LinkCapture.app/Info.plist", plistlib.dumps(info))
        return output.getvalue()

    def test_reads_build_from_binary_metadata(self):
        info, privacy = inspect_ipa(self.ipa())
        self.assertEqual(info["CFBundleVersion"], "2")
        self.assertEqual(privacy, {})

    def test_refuses_other_bundle(self):
        with self.assertRaises(AssertionError):
            inspect_ipa(self.ipa(CFBundleIdentifier="another.bundle"))

    def test_refuses_false_version(self):
        with self.assertRaises(AssertionError):
            inspect_ipa(self.ipa(CFBundleVersion="latest"))


if __name__ == "__main__":
    unittest.main()
