"""构建「零依赖 zip」与「单文件 exe」两种 Windows 分发物。

用法（Windows，Python 3.9+，需先 pip install pyinstaller）：
    python build.py --release <Release目录> --repo <仓库根> --out <输出目录> \
        --pyinstaller-home <pyinstaller 安装目录>

产物：
    <out>/routine_reminder-v<版本>-windows.zip       整目录绿色包（含 VC++ 运行库）
    <out>/routine_reminder-v<版本>-windows-single.exe 单文件启动器

版本号唯一来源是 `pubspec.yaml` 的 `version:`（`0.10.0+1` → `v0.10.0`），
exe 的版本资源由 `version_info.txt` 模板当场渲染，不另存一份数字。

注意：所有中间文件都放在 %TEMP% 的纯 ASCII 路径下。Flutter / PyInstaller
在中文路径下会出现读不到产物的怪问题，不要直接拿仓库目录当工作区。
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
import zipfile

VERSION = "0.0.0"
BUILD = 0
FOLDER = "routine_reminder-v%s" % VERSION
ZIP_NAME = FOLDER + "-windows.zip"
EXE_STEM = FOLDER + "-windows-single"
VC_DLLS = ("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")
EXTRA_DOCS = ("README.md", "LICENSE")


def read_version(repo: str) -> tuple[str, int]:
    """从 pubspec.yaml 读版本，返回 (x.y.z, build)。"""
    path = os.path.join(repo, "pubspec.yaml")
    try:
        with open(path, encoding="utf-8") as handle:
            for line in handle:
                if line.startswith("version:"):
                    raw = line.split(":", 1)[1].strip()
                    base, _, build = raw.partition("+")
                    number = int(build) if build.strip().isdigit() else 0
                    if not base.strip():
                        break
                    return base.strip(), number
    except OSError as exc:
        raise SystemExit("读不到 %s：%s" % (path, exc))
    raise SystemExit("pubspec.yaml 缺少 version 字段：%s" % path)


def apply_version(repo: str) -> None:
    global VERSION, BUILD, FOLDER, ZIP_NAME, EXE_STEM
    VERSION, BUILD = read_version(repo)
    FOLDER = "routine_reminder-v%s" % VERSION
    ZIP_NAME = FOLDER + "-windows.zip"
    EXE_STEM = FOLDER + "-windows-single"


def prepare_bundle(work: str, release: str, repo: str) -> str:
    bundle = os.path.join(work, "bundle")
    os.makedirs(bundle, exist_ok=True)
    shutil.copytree(release, bundle, dirs_exist_ok=True)

    system_root = os.environ.get("SystemRoot", r"C:\Windows")
    for dll in VC_DLLS:
        source = os.path.join(system_root, "System32", dll)
        if not os.path.isfile(source):
            raise SystemExit("缺少 VC++ 可再发行组件：%s" % source)
        shutil.copy2(source, os.path.join(bundle, dll))

    for name in EXTRA_DOCS:
        source = os.path.join(repo, name)
        if os.path.isfile(source):
            shutil.copy2(source, os.path.join(bundle, name))

    main_exe = os.path.join(bundle, "routine_reminder.exe")
    app_so = os.path.join(bundle, "data", "app.so")
    for required in (main_exe, app_so):
        if not os.path.isfile(required):
            raise SystemExit("运行包不完整：%s" % required)
    return bundle


def list_files(root: str) -> list[str]:
    return sorted(
        os.path.relpath(os.path.join(base, name), root).replace("\\", "/")
        for base, _, names in os.walk(root)
        for name in names
    )


def make_zip(bundle: str, out: str) -> str:
    path = os.path.join(out, ZIP_NAME)
    names = list_files(bundle)
    with zipfile.ZipFile(path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for name in names:
            archive.write(os.path.join(bundle, name), FOLDER + "/" + name)
    return path


def render_version_info(src: str, template: str) -> str:
    """把版本号渲染进 PyInstaller 的版本资源模板。"""
    with open(template, encoding="utf-8") as handle:
        text = handle.read()
    parts = [int(p) if p.isdigit() else 0 for p in VERSION.split(".")]
    parts = (parts + [0, 0, 0])[:3]
    text = text.replace("__VERSION_QUAD__", "(%d, %d, %d, %d)" % (*parts, BUILD))
    text = text.replace("__VERSION_FULL__", "%d.%d.%d.%d" % (*parts, BUILD))
    text = text.replace("__EXE_NAME__", EXE_STEM + ".exe")
    target = os.path.join(src, "version_info.txt")
    with open(target, "w", encoding="utf-8") as handle:
        handle.write(text)
    return target


def make_exe(work: str, bundle: str, repo: str, out: str, pyinstaller_home: str) -> str:
    src = os.path.join(work, "src")
    os.makedirs(src, exist_ok=True)
    here = os.path.dirname(os.path.abspath(__file__))
    shutil.copy2(os.path.join(here, "launcher.py"), os.path.join(src, "launcher.py"))
    version_file = render_version_info(src, os.path.join(here, "version_info.txt"))
    icon = os.path.join(repo, "windows", "runner", "resources", "app_icon.ico")
    if not os.path.isfile(icon):
        raise SystemExit("缺少应用图标：%s" % icon)
    shutil.copy2(icon, os.path.join(src, "app_icon.ico"))

    # 整包先压成单个 zip 再内嵌：PyInstaller 对散落的 dll 不做有效压缩，
    # 直接 --add-data 一个目录会让单 exe 从约 19 MB 膨胀到约 30 MB。
    archive = os.path.join(src, "bundle.zip")
    with zipfile.ZipFile(archive, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as packed:
        for name in list_files(bundle):
            packed.write(os.path.join(bundle, name.replace("/", os.sep)), name)

    env = os.environ.copy()
    env["PYTHONPATH"] = pyinstaller_home + os.pathsep + env.get("PYTHONPATH", "")
    env["PYINSTALLER_RESET_ENVIRONMENT"] = "1"

    command = [
        sys.executable, "-m", "PyInstaller",
        "--onefile", "--noconsole", "--clean", "-y", "--log-level", "WARN",
        "--name", EXE_STEM,
        "--icon", os.path.join(src, "app_icon.ico"),
        "--version-file", version_file,
        "--add-data", archive + os.pathsep + ".",
        "--distpath", os.path.join(work, "dist"),
        "--workpath", os.path.join(work, "build"),
        "--specpath", src,
        os.path.join(src, "launcher.py"),
    ]
    print("[build] running PyInstaller ...", flush=True)
    completed = subprocess.run(command, cwd=src, env=env, check=False)
    if completed.returncode != 0:
        raise SystemExit("PyInstaller 失败，退出码 %d" % completed.returncode)

    built = os.path.join(work, "dist", EXE_STEM + ".exe")
    if not os.path.isfile(built):
        raise SystemExit("没找到生成物：%s" % built)
    target = os.path.join(out, EXE_STEM + ".exe")
    shutil.copy2(built, target)
    return target


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", required=True, help="flutter build windows --release 产物目录")
    parser.add_argument("--repo", required=True, help="仓库根目录")
    parser.add_argument("--out", required=True, help="输出目录")
    parser.add_argument("--pyinstaller-home", default="", help="pyinstaller 的 --target 安装目录")
    parser.add_argument("--skip-exe", action="store_true")
    args = parser.parse_args()

    release = os.path.abspath(args.release)
    repo = os.path.abspath(args.repo)
    out = os.path.abspath(args.out)
    os.makedirs(out, exist_ok=True)
    apply_version(repo)
    print("[build] version: v%s (%s)" % (VERSION, FOLDER), flush=True)

    work = tempfile.mkdtemp(prefix="rr_dist_")
    try:
        bundle = prepare_bundle(work, release, repo)
        names = list_files(bundle)
        total = sum(os.path.getsize(os.path.join(bundle, n.replace("/", os.sep))) for n in names)
        print("[build] bundle: %d files / %d bytes" % (len(names), total), flush=True)
        for name in names:
            print("        " + name, flush=True)

        zip_path = make_zip(bundle, out)
        print("[build] zip -> %s (%d bytes)" % (zip_path, os.path.getsize(zip_path)), flush=True)

        if not args.skip_exe:
            exe_path = make_exe(work, bundle, repo, out, args.pyinstaller_home)
            print("[build] exe -> %s (%d bytes)" % (exe_path, os.path.getsize(exe_path)), flush=True)
        return 0
    finally:
        shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
