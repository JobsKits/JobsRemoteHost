# -*- mode: python ; coding: utf-8 -*-

from pathlib import Path
import os
import sys
from PyInstaller.utils.hooks import collect_submodules

project_dir = Path(SPEC).resolve().parent
entry_file = project_dir / "JobsRemoteHost.py"
cloudflared_name = "cloudflared.exe" if os.name == "nt" else "cloudflared"
cloudflared_path = project_dir / "tools" / cloudflared_name
binaries = [(str(cloudflared_path), "bin")] if cloudflared_path.is_file() else []

a = Analysis(
    [str(entry_file)],
    pathex=[str(project_dir)],
    binaries=binaries,
    datas=[],
    hiddenimports=collect_submodules("pynput"),
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(a.pure)

if sys.platform == "darwin":
    exe = EXE(
        pyz,
        a.scripts,
        [],
        exclude_binaries=True,
        name="JobsRemoteHost",
        debug=False,
        bootloader_ignore_signals=False,
        strip=False,
        upx=True,
        console=False,
        disable_windowed_traceback=False,
        argv_emulation=False,
        target_arch=None,
        codesign_identity=None,
        entitlements_file=None,
    )
    coll = COLLECT(
        exe,
        a.binaries,
        a.datas,
        strip=False,
        upx=True,
        upx_exclude=[],
        name="JobsRemoteHost",
    )
    app = BUNDLE(
        coll,
        name="JobsRemoteHost.app",
        icon=None,
        bundle_identifier="com.jobs.remotehost.python",
        info_plist={
            "NSHighResolutionCapable": True,
            "LSMinimumSystemVersion": "12.0",
        },
    )
else:
    exe = EXE(
        pyz,
        a.scripts,
        a.binaries,
        a.datas,
        [],
        name="JobsRemoteHost",
        debug=False,
        bootloader_ignore_signals=False,
        strip=False,
        upx=True,
        console=False,
        disable_windowed_traceback=False,
    )
