"""Build the free AltStore Classic catalogue from actual public release IPAs.

No version, build, size, minimum OS or hash is inferred from a tag or filename.
The current public AltStore AppVersion decoder and VerifyAppOperation support
sha256. Include it for compatible clients and publish a separate integrity report.
"""
import hashlib
import io
import json
import os
import plistlib
import re
import urllib.request
from pathlib import Path
from zipfile import ZipFile

REPO = "largartozaulnj/linkcapture-ios-native"
BUNDLE = "org.linkcapture.experimental"
BASE = "https://largartozaulnj.github.io/linkcapture-ios-native"


def get(url, api=False):
    headers = {"User-Agent": "LinkCapture-official-catalogue"}
    if api and os.environ.get("GH_TOKEN"):
        headers["Authorization"] = "Bearer " + os.environ["GH_TOKEN"]
    with urllib.request.urlopen(urllib.request.Request(url, headers=headers), timeout=60) as response:
        return response.read()


def inspect_ipa(data):
    with ZipFile(io.BytesIO(data)) as archive:
        assert archive.testzip() is None, "Corrupt IPA"
        paths = [p for p in archive.namelist() if re.fullmatch(r"Payload/[^/]+\.app/Info\.plist", p)]
        assert len(paths) == 1, "Expected one app"
        info = plistlib.loads(archive.read(paths[0]))
        assert info["CFBundleIdentifier"] == BUNDLE, "Bundle ID mismatch"
        for key in ("CFBundleShortVersionString", "CFBundleVersion"):
            assert re.fullmatch(r"\d+(?:\.\d+){0,3}", info[key]), "Invalid version/build"
        assert info["MinimumOSVersion"] == "16.0", "Unexpected deployment target"
        privacy = {k: v for k, v in info.items() if k.startswith("NS") and k.endswith("UsageDescription")}
        return info, privacy


def validate(source):
    assert source["name"] and source["apps"] and source["news"] == []
    app = source["apps"][0]
    assert app["bundleIdentifier"] == BUNDLE and app["developerName"] and app["iconURL"].startswith(BASE)
    assert isinstance(app["appPermissions"]["entitlements"], list)
    assert isinstance(app["appPermissions"]["privacy"], dict)
    pairs = set()
    for version in app["versions"]:
        pair = (version["version"], version["buildVersion"])
        assert pair not in pairs, "Duplicate version/build"
        pairs.add(pair)
        assert version["size"] > 0 and isinstance(version["size"], int)
        assert version["downloadURL"].startswith(f"https://github.com/{REPO}/releases/download/")
        assert version["date"] and version["localizedDescription"] and version["minOSVersion"] == "16.0"
        assert re.fullmatch(r"[a-f0-9]{64}", version["sha256"])
    assert app["versions"], "No installable release"


def main():
    releases = []
    page = 1
    while True:
        batch = json.loads(get(f"https://api.github.com/repos/{REPO}/releases?per_page=100&page={page}", api=True))
        assert isinstance(batch, list), "GitHub release query failed"
        releases.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    releases.sort(key=lambda r: r["published_at"] or "", reverse=True)
    versions, integrity, seen = [], [], {}
    privacy = {}
    for release in releases:
        if release["draft"]:
            continue
        assets = [a for a in release["assets"] if a["name"] == "LinkCapture-experimental-UNSIGNED.ipa"]
        if not assets:
            continue
        assert len(assets) == 1
        asset = assets[0]
        raw = get(asset["browser_download_url"])
        assert len(raw) == asset["size"], "Release asset size mismatch"
        info, permissions = inspect_ipa(raw)
        pair = (info["CFBundleShortVersionString"], info["CFBundleVersion"])
        digest = hashlib.sha256(raw).hexdigest()
        if pair in seen:
            # Old experimental builds all declared 0.1.0 (1). Only the newest
            # visual release can represent that pair; never fabricate versions.
            assert pair == ("0.1.0", "1") or digest == seen[pair], "New release reused version/build with different bytes"
            continue
        seen[pair] = digest
        privacy.update(permissions)
        versions.append({"version": pair[0], "buildVersion": pair[1], "date": release["published_at"],
                         "localizedDescription": release["body"] or release["name"],
                         "downloadURL": asset["browser_download_url"], "size": len(raw),
                         "minOSVersion": info["MinimumOSVersion"], "sha256": digest})
        integrity.append({"version": pair[0], "buildVersion": pair[1], "downloadURL": asset["browser_download_url"],
                          "size": len(raw), "sha256": digest, "release": release["html_url"]})
    def number(value):
        return tuple(int(part) for part in value.split("."))
    versions.sort(key=lambda v: (number(v["version"]), number(v["buildVersion"])), reverse=True)
    source = {"name": "LinkCapture — fonte oficial", "identifier": "org.linkcapture.source",
              "sourceURL": BASE + "/source.json", "subtitle": "Navegador nativo experimental para iPhone",
              "description": "Atualizações gratuitas do LinkCapture. Assinatura e instalação são autorizadas por você no AltStore Classic.",
              "website": BASE + "/", "iconURL": BASE + "/icon.png", "tintColor": "#78E0BA",
              "apps": [{"name": "LinkCapture", "bundleIdentifier": BUNDLE, "developerName": "LinkCapture",
                        "localizedDescription": "WKWebView interno, interface compacta, recuperação experimental e lembretes locais de renovação.",
                        "iconURL": BASE + "/icon.png", "tintColor": "#78E0BA", "category": "utilities",
                        "versions": versions, "appPermissions": {"entitlements": [], "privacy": privacy}}], "news": []}
    validate(source)
    docs = Path("docs")
    docs.mkdir(exist_ok=True)
    (docs / "source.json").write_text(json.dumps(source, ensure_ascii=False, indent=2), encoding="utf-8")
    (docs / "integrity.json").write_text(json.dumps(integrity, indent=2), encoding="utf-8")
    print(json.dumps({"versions": [(v["version"], v["buildVersion"], v["size"]) for v in versions],
                      "source": BASE + "/source.json", "validatedAgainstActualIPAs": True}, indent=2))


if __name__ == "__main__":
    main()
