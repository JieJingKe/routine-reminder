"""单文件版启动器（被 PyInstaller 打包成 onefile exe）。

为什么一定要「固定目录」：
主程序的开机自启会把 Platform.resolvedExecutable 的绝对路径写进
HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Run。PyInstaller 的
onefile 每次运行都解压到不同的 _MEIxxxxxx 临时目录、退出即删，直接在那儿
启动会让自启指向一个失效路径。所以这里先把内嵌运行包释放到
%LOCALAPPDATA%\\Programs\\routine-reminder\\，主程序始终从固定目录运行。

运行包以压缩的 bundle.zip 内嵌（比把散落的 dll 直接塞进 exe 小约 11 MB），
用 zip 自身的 MD5 当版本指纹：内容一致就跳过释放，直接启动。

自检开关：传 --extract-only 时只释放、不启动主程序，结果写到
%TEMP%\\rr_launcher_probe.txt，便于无人值守验证落盘完整性。
"""

from __future__ import annotations

import ctypes
import hashlib
import os
import shutil
import subprocess
import sys
import zipfile

APP_FOLDER = "routine-reminder"
MAIN_EXE = "routine_reminder.exe"


def bundle_archive() -> str:
    base = getattr(sys, "_MEIPASS", None)
    if base:
        return os.path.join(base, "bundle.zip")
    return os.path.join(os.path.dirname(os.path.abspath(__file__)), "bundle.zip")


def target_dir() -> str:
    local = os.environ.get("LOCALAPPDATA")
    if not local:
        local = os.path.join(os.path.expanduser("~"), "AppData", "Local")
    return os.path.join(local, "Programs", APP_FOLDER)


def probe_log() -> str:
    return os.path.join(os.environ.get("TEMP", os.getcwd()), "rr_launcher_probe.txt")


def md5_of(path: str) -> str:
    digest = hashlib.md5()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def write_log(text: str) -> None:
    try:
        with open(probe_log(), "w", encoding="utf-8") as handle:
            handle.write(text)
    except OSError:
        pass


def main() -> int:
    extract_only = "--extract-only" in sys.argv[1:]
    archive = bundle_archive()
    target = target_dir()

    try:
        fingerprint = md5_of(archive)
        stamp = os.path.join(target, ".stamp")
        main_exe = os.path.join(target, MAIN_EXE)
        cached = (
            os.path.isfile(main_exe)
            and os.path.isfile(stamp)
            and open(stamp, encoding="utf-8").read().strip() == fingerprint
        )

        if not cached:
            if os.path.isdir(target):
                shutil.rmtree(target)
            os.makedirs(target, exist_ok=True)
            with zipfile.ZipFile(archive) as packed:
                packed.extractall(target)
            with open(stamp, "w", encoding="utf-8") as handle:
                handle.write(fingerprint)

        if extract_only:
            names = sorted(
                os.path.relpath(os.path.join(root, name), target)
                for root, _, files in os.walk(target)
                for name in files
            )
            app_md5 = md5_of(os.path.join(target, "data", "app.so"))
            write_log(
                "OK\n%s\n%s\napp_so_md5=%s\ncached=%s\nfiles=%d\n%s\n"
                % (target, fingerprint, app_md5, cached, len(names), "\n".join(names))
            )
            return 0

        subprocess.Popen([main_exe], cwd=target, close_fds=True)
        return 0
    except Exception as error:  # noqa: BLE001 - 启动器要把任何异常都留痕
        write_log("ERR\n%r\n" % (error,))
        if not extract_only and os.name == "nt":
            try:
                ctypes.windll.user32.MessageBoxW(0, str(error), "我的时间 · 启动失败", 0x10)
            except Exception:
                pass
        return 1


if __name__ == "__main__":
    sys.exit(main())
