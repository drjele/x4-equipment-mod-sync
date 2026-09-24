import argparse
import ast
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ElementTree
from pathlib import Path

REPOSITORY_ROOT = Path(__file__).resolve().parents[1]
TEXT_SUFFIX = {".lua", ".py", ".sh", ".xml", ".md", ".toml", ".txt", ".yml", ".yaml"}
TEXT_NAME = {".editorconfig", ".gitattributes", ".gitignore", ".shellcheckrc", "LICENSE"}


def run_command(argument):
    result = subprocess.run(argument, cwd=REPOSITORY_ROOT, check=False)
    return 0 == result.returncode


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--fix", action="store_true", help="format code and normalize text whitespace"
    )
    option = parser.parse_args()
    for tool in ("ruff", "shellcheck", "shfmt"):
        if None is shutil.which(tool):
            print(f"missing development tool: {tool}", file=sys.stderr)
            return 1

    result = subprocess.run(
        ["git", "ls-files", "--cached", "--others", "--exclude-standard", "-z"],
        cwd=REPOSITORY_ROOT,
        check=True,
        capture_output=True,
    )
    file_name = sorted(set(result.stdout.decode().split("\0")) - {""})
    shell_file = []
    valid = True
    for name in file_name:
        path = REPOSITORY_ROOT / name
        if False == path.is_file():
            continue
        if path.suffix not in TEXT_SUFFIX and path.name not in TEXT_NAME:
            continue
        try:
            original = path.read_bytes().decode("utf-8")
            normalized = "\n".join(line.rstrip() for line in original.splitlines()) + "\n"
            if "" == original:
                normalized = ""
            if original != normalized:
                if True == option.fix:
                    path.write_bytes(normalized.encode("utf-8"))
                else:
                    print(f"{name}: expected lf, a final newline and no trailing whitespace")
                    valid = False
            if "\t" in normalized:
                print(f"{name}: use spaces instead of tabs")
                valid = False
            if ".xml" == path.suffix:
                ElementTree.fromstring(normalized)
            elif ".py" == path.suffix:
                ast.parse(normalized, filename=name)
            elif ".sh" == path.suffix:
                shell_file.append(name)
                valid = run_command(["bash", "-n", name]) and valid
        except (UnicodeError, SyntaxError, ElementTree.ParseError) as error:
            print(f"{name}: {error}", file=sys.stderr)
            valid = False

    valid = (
        run_command(["ruff", "format", *([] if True == option.fix else ["--check"]), "."]) and valid
    )
    valid = run_command(["ruff", "check", "."]) and valid
    if 0 < len(shell_file):
        valid = run_command(["shfmt", "-w" if True == option.fix else "-d", *shell_file]) and valid
        valid = run_command(["shellcheck", "--external-sources", *shell_file]) and valid
    return 0 if True == valid else 1


if "__main__" == __name__:
    sys.exit(main())
