#!/usr/bin/env python3
"""
Build script for FastWeather
Creates a standalone Windows executable using PyInstaller
"""

import os
import sys
import shutil
import subprocess

def main():
    print("=" * 60)
    print("FastWeather Build Script")
    print("=" * 60)
    print()
    
    # Check if PyInstaller is installed
    try:
        import PyInstaller
        print("✓ PyInstaller found")
    except ImportError:
        print("✗ PyInstaller not found")
        print("\nInstalling PyInstaller...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "pyinstaller"])
        print("✓ PyInstaller installed")

    # Check for app dependencies
    print("Checking dependencies...")
    missing_deps = []
    try:
        import wx
        print("✓ wxPython found")
    except ImportError:
        missing_deps.append("wxPython")
    
    try:
        import requests
        print("✓ requests found")
    except ImportError:
        missing_deps.append("requests")
        
    if missing_deps:
        print(f"✗ Missing dependencies: {', '.join(missing_deps)}")
        print("Installing dependencies...")
        subprocess.check_call([sys.executable, "-m", "pip", "install", "-r", "requirements.txt"])
        print("✓ Dependencies installed")
    
    print()
    
    # Clean previous builds
    print("Cleaning previous builds...")
    for folder in ['build', 'dist']:
        if os.path.exists(folder):
            try:
                shutil.rmtree(folder)
                print(f"  Removed {folder}/")
            except Exception as e:
                print(f"  Warning: Could not remove {folder}/: {e}")

    
    # Remove spec file if it exists
    spec_file = "fastweather.spec"
    if os.path.exists(spec_file):
        os.remove(spec_file)
        print(f"  Removed {spec_file}")
    
    print("✓ Cleanup complete")
    print()
    
    # Build the executable
    print("Building executable...")
    print("-" * 60)
    
    # PyInstaller command
    #
    # --onedir, NOT --onefile. A one-file build unpacks itself to a _MEIxxxx
    # temp directory at startup and deletes it on exit; when that delete fails
    # (antivirus still scanning it, a handle still open) the bootloader shows a
    # modal "Failed to remove temporary directory" warning and the process stays
    # alive holding WeatherFast.exe open. That breaks the in-app updater every
    # time: the installer cannot replace a locked file ("DeleteFile failed; code
    # 5"). One-file also splits into a bootloader parent plus a child process,
    # and only the child holds the AppMutex the installer looks for - so the
    # installer's running-app check misses the parent that owns the lock.
    # One-dir has no extraction step and runs as a single process, which removes
    # both problems and starts faster.
    cmd = [
        sys.executable, "-m", "PyInstaller",
        "--noconfirm", # Overwrite output directory
        "--name=WeatherFast",
        "--windowed",  # No console window
        "--onedir",    # Folder build (see note above - do not use --onefile)
        "--icon=NONE", # No icon (you can add one later)
        "--add-data", "city.json;.", # Embed city.json as a resource
        "--add-data", "us-cities-cached.json;.", # Embed US cities cache
        "--add-data", "international-cities-cached.json;.", # Embed international cities cache
        "--hidden-import=wx", # Explicitly include wxPython
        "--collect-all=wx", # Collect all wxPython modules and resources
        "--exclude-module=tkinter", # Exclude unnecessary standard library GUI
        "fastweather.py"
    ]
    
    print(f"Running: {' '.join(cmd)}")
    print()
    
    try:
        subprocess.check_call(cmd)
    except subprocess.CalledProcessError as e:
        print(f"\n✗ Build failed with error code {e.returncode}")
        return 1
    
    print()
    print("-" * 60)
    print("✓ Build complete!")
    print()
    
    # Check output. --onedir puts everything in dist/WeatherFast/.
    app_dir = os.path.join("dist", "WeatherFast")
    exe_path = os.path.join(app_dir, "WeatherFast.exe")

    if not os.path.exists(exe_path):
        print("✗ Build output not found!")
        return 1

    print(f"Application folder: {os.path.abspath(app_dir)}")
    print()

    total = sum(
        os.path.getsize(os.path.join(root, f))
        for root, _, files in os.walk(app_dir)
        for f in files
    )
    print(f"Folder size: {total / (1024 * 1024):.1f} MB")
    print()

    # Portable download: the whole folder, zipped. A one-dir build has no
    # single portable .exe (see the --onedir note above).
    zip_path = shutil.make_archive(
        os.path.join("dist", "WeatherFast-portable"), "zip", "dist", "WeatherFast")
    print(f"Portable zip: {os.path.abspath(zip_path)} "
          f"({os.path.getsize(zip_path) / (1024 * 1024):.1f} MB)")
    print()

    print("To distribute:")
    print("  Installer: build installer/weatherfast.iss over dist/WeatherFast.")
    print("  Portable:  share WeatherFast-portable.zip (extract the folder and run).")
    print()
    
    print()
    print("=" * 60)
    print("Build successful! 🎉")
    print("=" * 60)
    
    return 0

if __name__ == "__main__":
    sys.exit(main())
