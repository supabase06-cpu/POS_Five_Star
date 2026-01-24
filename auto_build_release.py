#!/usr/bin/env python3
"""
Five Star Chicken POS - Automated Build & Release Script
Increments version, builds, signs, and pushes to GitHub securely.
"""

import os
import re
import subprocess
import sys
import shutil
from pathlib import Path
from dotenv import load_dotenv

# Load environment variables from .env file
load_dotenv()

# Configuration
GITHUB_REPO = "https://github.com/supabase06-cpu/POS_Five_Star.git"
GITHUB_TOKEN = os.getenv("GITHUB_TOKEN")
CERT_PASSWORD = os.getenv("CERT_PASSWORD")

def run_command(cmd, check=True, shell=True, mask=True):
    """Run a command and return the result, masking tokens in logs"""
    log_cmd = cmd
    if mask and GITHUB_TOKEN and GITHUB_TOKEN in cmd:
        log_cmd = cmd.replace(GITHUB_TOKEN, "********")
    
    print(f"🔄 Running: {log_cmd}")
    try:
        result = subprocess.run(cmd, shell=shell, check=check, 
                              capture_output=True, text=True)
        if result.stdout:
            print(f"✅ Output: {result.stdout.strip()}")
        return result
    except subprocess.CalledProcessError as e:
        err_msg = e.stderr.replace(GITHUB_TOKEN, "********") if (mask and GITHUB_TOKEN) else e.stderr
        print(f"❌ Error: {e.returncode}")
        print(f"❌ Output: {err_msg}")
        if check:
            sys.exit(1)
        return e

def check_git_security():
    """Safety check: ensure .env is not being tracked by git"""
    result = subprocess.run("git ls-files .env", shell=True, capture_output=True, text=True)
    if ".env" in result.stdout:
        print("🚨 SECURITY ALERT: .env file is staged in Git!")
        print("Attempting to fix: Removing .env from Git tracking...")
        subprocess.run("git rm --cached .env", shell=True)
        if not Path(".gitignore").exists() or ".env" not in Path(".gitignore").read_text():
            with open(".gitignore", "a") as f:
                f.write("\n.env\n")
        print("✅ Fixed. .env is now ignored.")

def get_current_version():
    """Read current version from pubspec.yaml"""
    pubspec_path = Path("pubspec.yaml")
    if not pubspec_path.exists():
        print("❌ pubspec.yaml not found!")
        sys.exit(1)
    
    content = pubspec_path.read_text()
    version_match = re.search(r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)', content, re.MULTILINE)
    
    if not version_match:
        print("❌ Version not found in pubspec.yaml!")
        sys.exit(1)
    
    return map(int, version_match.groups())

def increment_version():
    """Increment version and update pubspec.yaml"""
    major, minor, patch, build = get_current_version()
    new_patch = patch + 1
    new_build = build + 1
    new_version = f"{major}.{minor}.{new_patch}+{new_build}"
    
    print(f"📈 Version: {major}.{minor}.{patch}+{build} → {new_version}")
    
    content = Path("pubspec.yaml").read_text()
    
    # Update Version
    content = re.sub(r'^version:\s*\d+\.\d+\.\d+\+\d+', f'version: {new_version}', content, flags=re.MULTILINE)
    
    # Update MSIX
    content = re.sub(r'msix_version:\s*\d+\.\d+\.\d+\.\d+', f'msix_version: {major}.{minor}.{new_patch}.0', content)
    
    # Update Output Name
    content = re.sub(
        r'output_name:\s*FiveStarChickenPOS_v\d+\.\d+\.\d+_Installer',
        f'output_name: FiveStarChickenPOS_v{major}.{minor}.{new_patch}_Installer',
        content
    )
    
    Path("pubspec.yaml").write_text(content)
    return major, minor, new_patch, new_build

def build_app():
    """Build the Flutter application"""
    print("🏗️ Building Flutter application...")
    run_command("flutter clean")
    run_command("flutter build windows --release")
    run_command("flutter pub run msix:create")
    return True

def sign_files(major, minor, patch, build):
    """Sign the built files"""
    print("🔐 Signing files...")
    
    exe_source = Path("build/windows/x64/runner/Release/five_star_chicken_enterprise.exe")
    msix_source = Path(f"build/windows/x64/runner/Release/FiveStarChickenPOS_v{major}.{minor}.{patch}_Installer.msix")
    
    exe_target = Path(f"FiveStarChickenPOS_v{major}.{minor}.{patch}_Signed.exe")
    msix_target = Path(f"FiveStarChickenPOS_v{major}.{minor}.{patch}_Signed.msix")
    
    if not exe_source.exists() or not msix_source.exists():
        print("❌ Build source files not found!")
        return False

    shutil.copy2(exe_source, exe_target)
    shutil.copy2(msix_source, msix_target)
    
    signtool_paths = [
        "C:\\Program Files (x86)\\Windows Kits\\10\\bin\\10.0.26100.0\\x64\\signtool.exe",
        "C:\\Program Files (x86)\\Windows Kits\\10\\bin\\10.0.22621.0\\x64\\signtool.exe",
        "C:\\Program Files (x86)\\Windows Kits\\10\\bin\\10.0.19041.0\\x64\\signtool.exe"
    ]
    
    signtool = next((p for p in signtool_paths if Path(p).exists()), None)
    
    if not signtool:
        print("❌ SignTool not found!")
        return False
    
    cert_path = Path("clinthoskote.pfx")
    sign_cmd_base = f'"{signtool}" sign /f "{cert_path}" /p "{CERT_PASSWORD}" /t http://timestamp.digicert.com /fd SHA256'
    
    run_command(f'{sign_cmd_base} "{exe_target}"')
    run_command(f'{sign_cmd_base} "{msix_target}"')
    
    return str(exe_target), str(msix_target)

def commit_and_push(major, minor, patch):
    """Commit changes and push to GitHub using token auth"""
    print("📤 Committing and pushing to GitHub...")
    
    run_command('git config user.name "Auto Build Bot"')
    run_command('git config user.email "build@fivestarchicken.com"')
    
    run_command('git add .')
    
    tag_name = f"v{major}.{minor}.{patch}"
    commit_msg = f"🚀 Release {tag_name} - Auto build with layout improvements"
    
    # Check if there's anything to commit
    st = subprocess.run("git diff --cached --quiet", shell=True)
    if st.returncode != 0:
        run_command(f'git commit -m "{commit_msg}"')
    
    # Handle Tag
    run_command(f'git tag -af {tag_name} -m "Release {tag_name}"')
    
    # Construct Authenticated URL
    repo_auth = GITHUB_REPO.replace("https://", f"https://{GITHUB_TOKEN}@")
    
    print("📤 Pushing to master branch...")
    # Use --force to overwrite the previous blocked/bad commit history if needed
    run_command(f'git push {repo_auth} master --force')
    run_command(f'git push {repo_auth} {tag_name} --force')
    
    print(f"✅ Successfully pushed {tag_name} to GitHub!")

def main():
    print("=" * 60)
    print("🚀 Five Star Chicken POS - Secure Auto Build & Release")
    print("=" * 60)
    
    if not GITHUB_TOKEN or not CERT_PASSWORD:
        print("❌ Missing credentials in .env file (GITHUB_TOKEN or CERT_PASSWORD)")
        return

    check_git_security()
    
    if input("\nContinue with build and release? (y/N): ").lower() != 'y':
        return
    
    try:
        major, minor, patch, build = increment_version()
        build_app()
        files = sign_files(major, minor, patch, build)
        
        if files:
            commit_and_push(major, minor, patch)
            print("\n" + "=" * 60)
            print(f"🎉 RELEASE COMPLETE: v{major}.{minor}.{patch}")
            print("=" * 60)
            
    except Exception as e:
        print(f"\n❌ Build failed: {e}")

if __name__ == "__main__":
    main()