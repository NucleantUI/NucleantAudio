#!/usr/bin/env python3
"""Build NucleantAudio's tests for Android and run them on a device or emulator.

    uv run Scripts/run_android_tests.py [--serial SERIAL] [-- <test arguments>]

The test product is a plain executable, run over `adb shell` from
/data/local/tmp — AAudio and the NDK's media codecs need no app around them —
with what it links pushed beside it: the Swift runtime from the Swift Android
SDK, and libc++_shared.so from that SDK's NDK sysroot. Its resource bundle
(the tests' fixtures) goes next to it too, where `Bundle.module` looks.

The device has to be running already (an emulator: `emulator -avd <name>`).
Its ABI picks the build: x86_64 or arm64-v8a, at API 28, the Swift Android
SDK's floor.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path

PACKAGE_ROOT = Path(__file__).resolve().parent.parent
SCRATCH = PACKAGE_ROOT / ".build" / "android"
DEVICE_DIR = "/data/local/tmp/nucleant-audio-tests"
API = 28
ARCHS = {"x86_64": "x86_64", "arm64-v8a": "aarch64"}


def find_adb() -> str:
    for candidate in [
        shutil.which("adb"),
        os.environ.get("ANDROID_HOME") and str(Path(os.environ["ANDROID_HOME"]) / "platform-tools" / "adb"),
        str(Path.home() / ".nucleant" / "android-sdk" / "platform-tools" / "adb"),
    ]:
        if candidate and Path(candidate).is_file():
            return candidate
    sys.exit("error: no adb found; put it on PATH or set ANDROID_HOME")


def find_android_sdk() -> Path:
    """The newest installed Swift Android SDK bundle's swift-android directory."""
    for root in (Path.home() / "Library" / "org.swift.swiftpm" / "swift-sdks", Path.home() / ".swiftpm" / "swift-sdks"):
        for bundle in sorted(root.glob("*_android.artifactbundle"), reverse=True):
            if (bundle / "swift-android" / "swift-sdk.json").is_file():
                return bundle / "swift-android"
    sys.exit("error: no Swift Android SDK installed")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--serial", help="the device, when more than one is attached")
    parser.add_argument("test_args", nargs="*", help="arguments for the test runner (after --)")
    args = parser.parse_args(argv)

    adb = [find_adb()] + (["-s", args.serial] if args.serial else [])
    abi = subprocess.run(adb + ["shell", "getprop", "ro.product.cpu.abi"], capture_output=True, text=True).stdout.strip()
    if abi not in ARCHS:
        sys.exit(f"error: no device, or one with an ABI this does not build for ({abi or 'none'})")
    arch = ARCHS[abi]

    command = ["swiftly", "run", "swift", "build", "--build-tests",
               "--swift-sdk", f"{arch}-unknown-linux-android{API}", "--scratch-path", str(SCRATCH)]
    print("+", " ".join(command), flush=True)
    if subprocess.run(command, cwd=PACKAGE_ROOT).returncode != 0:
        sys.exit("error: building the tests for Android failed")
    products = SCRATCH / "debug"
    tests = sorted(products.glob("*PackageTests.xctest"))
    if len(tests) != 1:
        sys.exit(f"error: expected one *PackageTests.xctest in {products}")

    sdk = find_android_sdk()
    runtime = sorted((sdk / "swift-resources" / "usr" / "lib" / f"swift-{arch}" / "android").glob("*.so"))
    libcxx = sdk / "ndk-sysroot" / "usr" / "lib" / f"{arch}-linux-android" / "libc++_shared.so"
    if not runtime or not libcxx.is_file():
        sys.exit(f"error: the Swift runtime or libc++_shared.so for {arch} is missing from {sdk}")

    subprocess.run(adb + ["shell", "rm", "-rf", DEVICE_DIR], check=True)
    subprocess.run(adb + ["shell", "mkdir", "-p", DEVICE_DIR], check=True)
    pushed = [*runtime, libcxx, tests[0], *sorted(products.glob("*.resources"))]
    print(f"[run_android_tests] pushing {len(pushed)} files to {DEVICE_DIR}", flush=True)
    for path in pushed:
        subprocess.run(adb + ["push", "-q", str(path), DEVICE_DIR], check=True)

    test_args = " ".join(["--testing-library", "swift-testing", *args.test_args])
    run = f"cd {DEVICE_DIR} && LD_LIBRARY_PATH=. ./{tests[0].name} {test_args}; echo \"exit status $?\""
    result = subprocess.run(adb + ["shell", run], capture_output=True, text=True)
    sys.stdout.write(result.stdout)
    sys.stderr.write(result.stderr)
    last = result.stdout.strip().splitlines()[-1] if result.stdout.strip() else ""
    status = int(last.removeprefix("exit status ")) if last.startswith("exit status ") else 1
    print(f"[run_android_tests] exit status {status}", flush=True)
    return status


if __name__ == "__main__":
    sys.exit(main())
