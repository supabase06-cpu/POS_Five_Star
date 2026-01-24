#!/usr/bin/env python3
"""
Five Star Chicken POS - Automated Build & Release Script
Increments version, builds, signs, and pushes to GitHub

Usage: python auto_build_release.py
"""

import os
import re
import subprocess
import sys
import json
import shutil
from pathlib import Path

# Configuration
GITHUB_REPO = "https://github.com/supabase06-cpu/POS_Five_Star.git"
GITHUB_TOKEN = "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"
CERT_PASSWORD = "StrongPassword123!"

def run_command(cmd, check=True, shell=True):
    """Run a command and return the result"""
    print(f"🔄 Running: {cmd}")
    try:
        result = subprocess.run(cmd, shell=shell, check=check, 
                              capture_output=True, text=True)
        if result.stdout:
            print(f"✅ Output: {result.stdout.strip()}")
        return result
    except subprocess.CalledProcessError as e:
        print(f"❌ Error: {e}")
        print(f"❌ Output: {e.stdout}")
        print(f"❌ Error: {e.stderr}")
        if check:
            sys.exit(1)
        return e

def get_current_version():
    """Read current version from pubspec.yaml"""
    pubspec_path = Path("pubspec.yaml")
    if not pubspec_path.exists():
        print("❌ pubspec.yaml not found!")
        sys.exit(1)
    
    with open(pubspec_path, 'r') as f:
        content = f.read()
    
    # Find version line
    version_match = re.search(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)', content, re.MULTILINE)
    if not version_match:
        print("❌ Version not found in pubspec.yaml!")
        sys.exit(1)
    
    major, minor, patch, build = map(int, version_match.groups())
    return major, minor, patch, build

def increment_version():
    """Increment version by +1 and update pubspec.yaml"""
    major, minor, patch, build = get_current_version()
    
    # Increment patch and build number
    new_patch = patch + 1
    new_build = build + 1
    new_version = f"{major}.{minor}.{new_patch}+{new_build}"
    
    print(f"📈 Version: {major}.{minor}.{patch}+{build} → {new_version}")
    
    # Update pubspec.yaml
    pubspec_path = Path("pubspec.yaml")
    with open(pubspec_path, 'r') as f:
        content = f.read()
    
    # Replace version line
    content = re.sub(
        r'^version:\s*\d+\.\d+\.\d+\+\d+',
        f'version: {new_version}',
        content,
        flags=re.MULTILINE
    )
    
    # Update MSIX version (remove +build part)
    msix_version = f"{major}.{minor}.{new_patch}.0"
    content = re.sub(
        r'msix_version:\s*\d+\.\d+\.\d+\.\d+',
        f'msix_version: {msix_version}',
        content
    )
    
    # Update output name
    content = re.sub(
        r'output_name:\s*FiveStarChickenPOS_v\d+\.\d+\.\d+_Installer',
        f'output_name: FiveStarChickenPOS_v{major}.{minor}.{new_patch}_Installer',
        content
    )
    
    with open(pubspec_path, 'w') as f:
        f.write(content)
    
    return major, minor, new_patch, new_build

def build_app():
    """Build the Flutter application"""
    print("🏗️ Building Flutter application...")
    
    # Clean previous build
    run_command("flutter clean")
    
    # Build Windows release
    run_command("flutter build windows --release")
    
    # Build MSIX package
    run_command("flutter pub run msix:create")
    
    return True

def sign_files(major, minor, patch, build):
    """Sign the built files"""
    print("🔐 Signing files...")
    
    # Use Path objects for cross-platform compatibility
    exe_source = Path("build/windows/x64/runner/Release/five_star_chicken_enterprise.exe")
    msix_source = Path(f"build/windows/x64/runner/Release/FiveStarChickenPOS_v{major}.{minor}.{patch}_Installer.msix")
    
    exe_target = Path(f"FiveStarChickenPOS_v{major}.{minor}.{patch}_Signed.exe")
    msix_target = Path(f"FiveStarChickenPOS_v{major}.{minor}.{patch}_Signed.msix")
    
    # Check if source files exist
    if not exe_source.exists():
        print(f"❌ EXE source file not found: {exe_source}")
        print("🔍 Checking build directory...")
        build_dir = Path("build/windows/x64/runner/Release")
        if build_dir.exists():
            print("📁 Files in build directory:")
            for file in build_dir.iterdir():
                print(f"   - {file.name}")
        return False
    
    if not msix_source.exists():
        print(f"❌ MSIX source file not found: {msix_source}")
        return False
    
    # Copy files using Python instead of Windows copy command
    import shutil
    try:
        print(f"📋 Copying {exe_source} → {exe_target}")
        shutil.copy2(exe_source, exe_target)
        
        print(f"📋 Copying {msix_source} → {msix_target}")
        shutil.copy2(msix_source, msix_target)
    except Exception as e:
        print(f"❌ Error copying files: {e}")
        return False
    
    # Find SignTool
    signtool_paths = [
        "C:\\Program Files (x86)\\Windows Kits\\10\\bin\\10.0.26100.0\\x64\\signtool.exe",
        "C:\\Program Files (x86)\\Windows Kits\\10\\bin\\10.0.19041.0\\x64\\signtool.exe",
        "C:\\Program Files (x86)\\Windows Kits\\10\\bin\\10.0.22621.0\\x64\\signtool.exe"
    ]
    
    signtool = None
    for path in signtool_paths:
        if Path(path).exists():
            signtool = path
            break
    
    if not signtool:
        print("❌ SignTool not found!")
        print("🔍 Searched paths:")
        for path in signtool_paths:
            print(f"   - {path}")
        return False
    
    cert_path = Path("clinthoskote.pfx")
    if not cert_path.exists():
        print("❌ Certificate not found!")
        return False
    
    print(f"🔧 Using SignTool: {signtool}")
    
    # Sign files
    sign_cmd_base = f'"{signtool}" sign /f "{cert_path}" /p "{CERT_PASSWORD}" /t http://timestamp.digicert.com /fd SHA256'
    
    print(f"🔐 Signing EXE: {exe_target}")
    run_command(f'{sign_cmd_base} "{exe_target}"')
    
    print(f"🔐 Signing MSIX: {msix_target}")
    run_command(f'{sign_cmd_base} "{msix_target}"')
    
    print(f"✅ Signed files created:")
    print(f"   - {exe_target}")
    print(f"   - {msix_target}")
    
    return str(exe_target), str(msix_target)

def setup_git():
    """Setup git configuration and initialize repository if needed"""
    print("🔧 Setting up Git...")
    
    # Check if we're in a git repository
    result = run_command('git status', check=False)
    if result.returncode != 0:
        print("📁 Initializing Git repository...")
        run_command('git init')
        
        # Create .gitignore if it doesn't exist
        gitignore_path = Path('.gitignore')
        if not gitignore_path.exists():
            gitignore_content = """# Flutter/Dart
.dart_tool/
.packages
.pub-cache/
.pub/
build/
.flutter-plugins
.flutter-plugins-dependencies

# IDE
.idea/
.vscode/
*.swp
*.swo
*~

# OS
.DS_Store
Thumbs.db

# Local database
*.db
*.sqlite

# Certificates (keep private)
# *.pfx

# Environment files
.env.local
.env.production

# Windows
*.exe
*.dll
*.pdb

# But keep signed releases
!*_Signed.exe
!*_Signed.msix
"""
            with open(gitignore_path, 'w') as f:
                f.write(gitignore_content)
            print("📝 Created .gitignore file")
    
    # Configure git
    run_command('git config user.name "Auto Build Bot"')
    run_command('git config user.email "build@fivestarchicken.com"')
    
    # Add remote if not exists
    result = run_command('git remote get-url origin', check=False)
    if result.returncode != 0:
        print(f"🔗 Adding remote origin: {GITHUB_REPO}")
        run_command(f'git remote add origin {GITHUB_REPO}')
    else:
        print("🔗 Remote origin already configured")

def commit_and_push(major, minor, patch, build):
    """Commit changes and push to GitHub"""
    print("📤 Committing and pushing to GitHub...")
    
    # Check if there are any changes to commit
    result = run_command('git status --porcelain', check=False)
    if not result.stdout.strip():
        print("ℹ️ No changes to commit")
    
    # Add files
    run_command('git add .')  # Add all files (respects .gitignore)
    
    # Check if there's anything staged
    result = run_command('git diff --cached --name-only', check=False)
    if not result.stdout.strip():
        print("ℹ️ No staged changes to commit")
        return
    
    # Commit
    commit_msg = f"🚀 Release v{major}.{minor}.{patch} - Auto build with cart layout improvements"
    run_command(f'git commit -m "{commit_msg}"')
    
    # Tag the release
    tag_name = f"v{major}.{minor}.{patch}"
    
    # Check if tag already exists
    result = run_command(f'git tag -l {tag_name}', check=False)
    if result.stdout.strip():
        print(f"⚠️ Tag {tag_name} already exists, deleting old tag")
        run_command(f'git tag -d {tag_name}', check=False)
    
    run_command(f'git tag -a {tag_name} -m "Release {tag_name}"')
    
    # Push with token authentication
    repo_with_token = GITHUB_REPO.replace("https://", f"https://{GITHUB_TOKEN}@")
    
    # Try to push to main branch first, if it fails try master
    print("📤 Pushing to main branch...")
    result = run_command(f'git push {repo_with_token} main', check=False)
    if result.returncode != 0:
        print("📤 Main branch failed, trying master branch...")
        run_command(f'git push {repo_with_token} master')
    
    # Push tags
    print("🏷️ Pushing tags...")
    run_command(f'git push {repo_with_token} {tag_name}')
    
    print(f"✅ Successfully pushed v{major}.{minor}.{patch} to GitHub!")

def main():
    """Main execution function"""
    print("=" * 60)
    print("🚀 Five Star Chicken POS - Auto Build & Release")
    print("=" * 60)
    print()
    print("This will:")
    print("  1. Increment version (+1)")
    print("  2. Build Flutter app")
    print("  3. Create and sign MSIX package")
    print("  4. Push to GitHub repository")
    print()
    
    # Get user confirmation
    try:
        confirm = input("Continue? (y/N): ").strip().lower()
        if confirm != 'y':
            print("❌ Cancelled by user")
            return
    except KeyboardInterrupt:
        print("\n❌ Cancelled by user")
        return
    
    try:
        # Check if we're in the right directory
        if not Path("pubspec.yaml").exists():
            print("❌ Not in Flutter project directory!")
            sys.exit(1)
        
        print("\n🚀 Starting automated build and release...")
        
        # Increment version
        major, minor, patch, build = increment_version()
        
        # Build application
        build_app()
        
        # Sign files
        result = sign_files(major, minor, patch, build)
        if not result:
            print("❌ Signing failed!")
            input("\nPress Enter to exit...")
            sys.exit(1)
        
        exe_file, msix_file = result
        
        # Setup git and push
        setup_git()
        commit_and_push(major, minor, patch, build)
        
        print("\n" + "=" * 60)
        print("🎉 BUILD & RELEASE COMPLETE!")
        print("=" * 60)
        print(f"📦 Version: v{major}.{minor}.{patch}")
        print(f"📁 Files created:")
        print(f"   - {exe_file}")
        print(f"   - {msix_file}")
        print(f"🌐 Pushed to: {GITHUB_REPO}")
        print("\n💡 Share the MSIX file with clients for installation!")
        
        input("\nPress Enter to exit...")
        
    except KeyboardInterrupt:
        print("\n❌ Build cancelled by user")
        sys.exit(1)
    except Exception as e:
        print(f"\n❌ Build failed: {e}")
        input("\nPress Enter to exit...")
        sys.exit(1)

if __name__ == "__main__":
    main()