#!/usr/bin/env python3
"""
Skill Installer - Installs .skill files to the skills directory

Usage:
    # Install a single .skill file
    python3 install_skill.py /path/to/coredump-data-download.skill

    # Install to custom directory
    python3 install_skill.py /path/to/coredump-data-download.skill --target ~/.claude/skills

    # List contents without installing
    python3 install_skill.py /path/to/coredump-data-download.skill --list

    # Install all .skill files in a directory
    python3 install_skill.py /path/to/skills/ --batch
"""

import json
import os
import sys
import zipfile
from pathlib import Path


def get_skill_info_from_zip(zip_path: Path) -> dict:
    """Extract skill info from SKILL.md inside the .skill file."""
    info = {"name": "", "description": "", "version": "1.0.0"}
    try:
        with zipfile.ZipFile(zip_path, 'r') as zf:
            # Find SKILL.md in the zip
            skill_md_name = None
            for name in zf.namelist():
                if name.endswith("SKILL.md"):
                    skill_md_name = name
                    break

            if not skill_md_name:
                return info

            content = zf.read(skill_md_name).decode("utf-8")

            # Parse YAML frontmatter
            if content.startswith("---"):
                end = content.find("---", 3)
                if end > 0:
                    frontmatter = content[3:end]
                    for line in frontmatter.split("\n"):
                        if line.startswith("name:"):
                            info["name"] = line.split(":", 1)[1].strip()
                        elif line.startswith("description:"):
                            info["description"] = line.split(":", 1)[1].strip()
    except Exception as e:
        print(f"  Warning: Could not parse SKILL.md: {e}")
    return info


def list_skill_contents(skill_file: Path) -> list:
    """List all files inside a .skill file."""
    files = []
    try:
        with zipfile.ZipFile(skill_file, 'r') as zf:
            for info in zf.infolist():
                if not info.is_dir():
                    files.append(info.filename)
    except Exception as e:
        print(f"❌ Error reading .skill file: {e}")
        return []
    return files


def install_skill(skill_file: Path, target_dir: Path, force: bool = False) -> bool:
    """
    Install a .skill file to the target directory.

    Args:
        skill_file: Path to the .skill file
        target_dir: Target skills directory
        force: Overwrite existing files

    Returns:
        True if installation was successful
    """
    skill_file = Path(skill_file).resolve()
    if not skill_file.exists():
        print(f"❌ .skill file not found: {skill_file}")
        return False

    if not skill_file.suffix == ".skill":
        print(f"❌ Not a .skill file: {skill_file}")
        return False

    # Get skill info
    info = get_skill_info_from_zip(skill_file)
    skill_name = info["name"] or skill_file.stem
    print(f"\n📦 Installing skill: {skill_name}")

    # Determine installation path
    # Skill is installed as skill_name/skill_contents
    install_path = target_dir / skill_name

    # Check if skill already exists
    if install_path.exists() and not force:
        print(f"⚠️  Skill already exists: {install_path}")
        print(f"   Use --force to overwrite")
        return False

    # Create target directory
    install_path.mkdir(parents=True, exist_ok=True)

    # Extract files
    extracted = []
    skipped = []
    protected = {"accounts.json"}  # Never overwrite these

    try:
        with zipfile.ZipFile(skill_file, 'r') as zf:
            for member in zf.namelist():
                member_path = Path(member)
                # Skip if it's a directory
                if member_path.name == "" or str(member).endswith("/"):
                    continue

                # Get the relative path inside the skill
                # .skill files store paths as skill_name/file.txt
                parts = member_path.parts
                if len(parts) < 2:
                    # File directly in skill root, skip
                    continue

                # The actual file path inside the skill
                dest_rel = Path(*parts[1:])

                # Check for protected files
                if dest_rel.name in protected and (install_path / dest_rel).exists():
                    skipped.append(str(dest_rel))
                    continue

                dest_path = install_path / dest_rel
                dest_path.parent.mkdir(parents=True, exist_ok=True)

                # Read and write file
                content = zf.read(member)
                dest_path.write_bytes(content)
                extracted.append(str(dest_rel))

        print(f"✅ Extracted {len(extracted)} files")

        # Generate install manifest
        manifest = {
            "skill_name": skill_name,
            "skill_file": str(skill_file),
            "installed_at": str(Path(__file__).stat().st_mtime) if os.path.exists(__file__) else None,
            "files": extracted,
            "skipped": skipped
        }
        manifest_path = install_path / ".skill_installed.json"
        manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False))

        if skipped:
            print(f"⚠️  Skipped {len(skipped)} protected files: {', '.join(skipped)}")

        print(f"📍 Installed to: {install_path}")
        return True

    except Exception as e:
        print(f"❌ Error installing skill: {e}")
        # Clean up partial installation
        if install_path.exists():
            import shutil
            shutil.rmtree(install_path)
        return False


def batch_install(skill_dir: Path, target_dir: Path, force: bool = False) -> list:
    """Install all .skill files from a directory."""
    if not skill_dir.exists():
        print(f"❌ Directory not found: {skill_dir}")
        return []

    skill_files = list(skill_dir.glob("*.skill"))
    if not skill_files:
        print(f"❌ No .skill files found in: {skill_dir}")
        return []

    print(f"📦 Found {len(skill_files)} .skill files in {skill_dir}")
    results = []
    for skill_file in skill_files:
        info = get_skill_info_from_zip(skill_file)
        skill_name = info["name"] or skill_file.stem
        print(f"\n[{skill_files.index(skill_file) + 1}/{len(skill_files)}] ", end="")
        success = install_skill(skill_file, target_dir, force)
        results.append((skill_name, success))

    return results


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)

    skill_path = sys.argv[1]
    target_dir = Path.home() / ".claude" / "skills"
    force = False
    list_only = False
    batch = False

    # Parse arguments
    args = sys.argv[2:]
    if "--target" in args:
        idx = args.index("--target")
        target_dir = Path(args[idx + 1]) if idx + 1 < len(args) else target_dir
    if "--force" in args or "-f" in args:
        force = True
    if "--list" in args:
        list_only = True
    if "--batch" in args:
        batch = True

    skill_path = Path(skill_path)

    # Handle directory with --batch
    if batch and skill_path.is_dir():
        print(f"📦 Batch install from: {skill_path}")
        print(f"📍 Target directory: {target_dir}")
        results = batch_install(skill_path, target_dir, force)

        print("\n" + "=" * 60)
        print("📊 Installation Summary:")
        success = sum(1 for _, r in results if r)
        total = len(results)
        print(f"   Success: {success}/{total}")
        for skill_name, result in results:
            status = "✅" if result else "❌"
            print(f"   {status} {skill_name}")
        sys.exit(0 if success == total else 1)

    # Single file or directory
    if skill_path.is_dir() and not batch:
        # List all .skill files in directory
        skill_files = list(skill_path.glob("*.skill"))
        print(f"📦 .skill files in {skill_path}:")
        for sf in skill_files:
            info = get_skill_info_from_zip(sf)
            print(f"   - {sf.name}")
            print(f"     Name: {info['name']}")
        sys.exit(0)

    if not skill_path.exists():
        print(f"❌ File not found: {skill_path}")
        sys.exit(1)

    if list_only:
        print(f"📦 Contents of {skill_path}:")
        files = list_skill_contents(skill_path)
        for f in files:
            print(f"   - {f}")
        info = get_skill_info_from_zip(skill_path)
        print(f"\n📝 Skill Info:")
        print(f"   Name: {info['name']}")
        print(f"   Description: {info['description']}")
        sys.exit(0)

    print(f"📦 Installing skill from: {skill_path}")
    print(f"📍 Target directory: {target_dir}")
    success = install_skill(skill_path, target_dir, force)
    sys.exit(0 if success else 1)


if __name__ == "__main__":
    main()
