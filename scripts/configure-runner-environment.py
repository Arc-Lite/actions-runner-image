#!/usr/bin/env python3
"""Resolve upstream environment values for Runner.Listener's literal .env parser."""

import os
import re
import shlex
from pathlib import Path
from string import Template


def configure(environment_file: Path, runner: Path, shell_file: Path) -> None:
    values = dict(os.environ)
    values["HOME"] = str(runner)
    configured = {}
    for raw in environment_file.read_text().splitlines():
        if not raw.strip() or raw.lstrip().startswith("#"):
            continue
        name, value = raw.split("=", 1)
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name):
            raise ValueError(f"Invalid environment variable: {name}")
        # .env does not understand shell quotes or variable expansion.
        # Expand upstream $HOME values without evaluating shell code.
        if value.startswith(('"', "'")):
            tokens = shlex.split(value)
            if len(tokens) != 1:
                raise ValueError(f"Invalid environment value: {raw}")
            value = tokens[0]
        value = Template(value).substitute(values)
        if "\n" in value or "\r" in value:
            raise ValueError(f"Multiline environment value: {name}")
        configured[name] = value
        values[name] = value

    configured["XDG_CONFIG_HOME"] = str(runner / ".config")
    configured["RUSTUP_HOME"] = str(runner / ".rustup")
    configured["CARGO_HOME"] = str(runner / ".cargo")
    configured["DOTNET_ROOT"] = "/usr/share/dotnet"
    configured["DOTNET_CLI_TELEMETRY_OPTOUT"] = "1"

    (runner / ".env").write_text("".join(f"{k}={v}\n" for k, v in configured.items()))
    (runner / ".path").write_text(configured["PATH"] + "\n")
    shell_file.write_text(
        "".join(f"export {k}={shlex.quote(v)}\n" for k, v in configured.items())
    )


if __name__ == "__main__":
    configure(
        Path("/etc/environment"),
        Path("/home/runner"),
        Path("/etc/runner-environment.sh"),
    )
