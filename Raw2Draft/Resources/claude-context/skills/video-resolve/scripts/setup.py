"""Verify DaVinci Resolve scripting environment is set up correctly.

Checks:
1. Resolve Studio is running
2. Python scripting module is accessible
3. Can connect and read project info

Usage:
    python3 setup.py
"""

import os
import subprocess
import sys


def check_resolve_running():
    """Check if DaVinci Resolve is running."""
    result = subprocess.run(
        ['pgrep', '-x', 'DaVinci Resolve'],
        capture_output=True,
    )
    return result.returncode == 0


def check_resolve_installed():
    """Check if DaVinci Resolve is installed."""
    app_path = "/Applications/DaVinci Resolve/DaVinci Resolve.app"
    return os.path.exists(app_path)


def main():
    print("DaVinci Resolve Setup Check")
    print("=" * 40)

    # Check installation
    installed = check_resolve_installed()
    print(f"  Installed: {'Yes' if installed else 'No'}")
    if not installed:
        print("\n  DaVinci Resolve is not installed.")
        print("  Download from: https://www.blackmagicdesign.com/products/davinciresolve")
        print("  Note: Scripting requires DaVinci Resolve Studio ($295 one-time)")
        sys.exit(1)

    # Check if running
    running = check_resolve_running()
    print(f"  Running: {'Yes' if running else 'No'}")
    if not running:
        print("\n  Please start DaVinci Resolve before running scripts.")
        sys.exit(1)

    # Check scripting module
    module_paths = [
        "/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules",
        os.path.expanduser("~/Library/Application Support/Blackmagic Design/DaVinci Resolve/Developer/Scripting/Modules"),
    ]

    module_found = False
    for p in module_paths:
        if os.path.isdir(p):
            print(f"  Scripting module: {p}")
            module_found = True
            sys.path.insert(0, p)
            break

    if not module_found:
        print("\n  Scripting module not found.")
        print("  This usually means you have the free version.")
        print("  DaVinci Resolve Studio ($295) is required for Python scripting.")
        sys.exit(1)

    # Try to connect
    try:
        import DaVinciResolveScript as dvr
        resolve = dvr.scriptapp("Resolve")
        if resolve is None:
            print("\n  Connected to scripting module but Resolve is not responding.")
            print("  Try restarting DaVinci Resolve.")
            sys.exit(1)

        print(f"  Product: {resolve.GetProductName()}")
        print(f"  Version: {resolve.GetVersionString()}")

        pm = resolve.GetProjectManager()
        project = pm.GetCurrentProject()
        if project:
            print(f"  Current project: {project.GetName()}")
        else:
            print("  No project currently open")

        print("\n  Setup OK — ready to use Resolve scripting.")

    except ImportError:
        print("\n  Cannot import DaVinciResolveScript module.")
        print("  Check that DaVinci Resolve Studio is properly installed.")
        sys.exit(1)
    except Exception as e:
        print(f"\n  Error connecting: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
