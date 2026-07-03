# Android build config for EpubViewer, used by PySide6's `pyside6-android-deploy` tool.
#
# IMPORTANT — this is a config *scaffold*, not a ready-to-run build:
#
# 1. `pyside6-android-deploy` wraps buildozer/python-for-android, which only runs on a
#    Linux (or macOS) host. It is NOT supported from native Windows -- run it from WSL2,
#    a Linux VM, or Qt's official android-deploy Docker image.
# 2. It requires a full local toolchain that is NOT installed by `pip install pyside6`:
#      - Android SDK + NDK (buildozer can auto-download these if [buildozer] ndk_path/
#        sdk_path below are left blank)
#      - A JDK (17+)
#      - Android-targeted PySide6 + shiboken6 wheels (cross-compiled for the target ABI --
#        these are DIFFERENT from the desktop wheels already in requirements.txt, and must
#        be downloaded separately; see https://doc.qt.io/qtforpython/deployment/deploy-android.html)
# 3. Fill in [android] wheel_pyside / wheel_shiboken below with paths to those wheels
#    before running the build.
#
# Once the toolchain and wheels are in place, run from the project root:
#   pyside6-android-deploy -c pysidedeploy-android.spec
#
# Touch navigation (tap zones + swipe) was added to the reader for this target; menu-bar
# actions (Open/Change Chapter/Viewer Settings) still work via Qt's Android widget rendering,
# but QFileDialog's native picker behavior on Android should be spot-checked on a device.

[app]

# Title of your application
title = EpubViewer

# Project root directory. Default: The parent directory of input_file
project_dir = .

# Source file entry point path. Default: main.py
input_file = main.py

# Directory where the executable output is generated
exec_directory = dist-android

# Path to the project file relative to project_dir
project_file =

# Application icon
icon =

[python]

# Python path
python_path =

# Python packages to install
packages = Nuitka==4.0

# Buildozer: for deploying Android application
android_packages = buildozer==1.5.0,cython==0.29.33

[qt]

# Paths to required QML files. Comma separated (not used -- this app is QWidgets-only)
qml_files =

# Excluded qml plugin binaries
excluded_qml_plugins =

# Qt modules used. Comma separated
modules = Core,Gui,Widgets

# Qt plugins used by the application. Only relevant for desktop deployment
plugins =

[android]

# Path to the Android-targeted PySide6 wheel (NOT the desktop wheel from requirements.txt)
wheel_pyside =

# Path to the Android-targeted Shiboken wheel
wheel_shiboken =

# Plugins to be copied to libs folder of the packaged application. Comma separated
plugins =

[nuitka]

mode = onefile
extra_args = --quiet --noinclude-qt-translations

[buildozer]

# Build mode: debug produces a .apk (installable directly for testing);
# release produces a .aab (for Play Store submission, needs signing).
mode = debug

# Path to PySide6 and shiboken6 recipe dir (leave blank to use buildozer's bundled recipes)
recipe_dir =

# Path to extra Qt Android .jar files to be loaded by the application
jars_dir =

# Leave blank to let buildozer download the NDK itself
ndk_path =

# Leave blank to let buildozer download the SDK itself
sdk_path =

# Other libraries to be loaded at app startup. Comma separated.
local_libs =

# arm64-v8a covers effectively all modern Android devices; add more via a
# comma-separated list if you also need to support older 32-bit hardware.
arch = aarch64
