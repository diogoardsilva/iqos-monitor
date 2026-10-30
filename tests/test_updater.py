from iqos_monitor import updater


def test_version_compare():
    assert updater.is_newer("0.2.0", "0.1.9")
    assert updater.is_newer("v1.0.0", "0.9.9")
    assert not updater.is_newer("0.1.0", "0.1.0")
    assert not updater.is_newer("0.1.0", "0.1.1")


def test_release_from_json():
    data = {"tag_name": "v1.2.3", "body": "notas", "html_url": "https://x",
            "assets": [{"name": "IqosMonitor.exe", "browser_download_url": "https://x/exe"},
                       {"name": "IqosMonitor.exe.sha256", "browser_download_url": "https://x/sha"}]}
    r = updater.release_from_json(data)
    assert (r.version, r.exe_url, r.sha256_url) == ("1.2.3", "https://x/exe", "https://x/sha")
    assert updater.release_from_json({**data, "prerelease": True}) is None
    assert updater.release_from_json({**data, "assets": []}) is None
