"""Dagger SDK bootstrap: scaffolding and compilation for Gleam modules.

Python is used only for the SDK's bootstrap hooks. User functions, schema
registration, argument decoding, and invocation run in Gleam on Erlang.
"""
from pathlib import PurePosixPath
import re
import tomllib
from typing import Annotated

import dagger
from dagger import DefaultPath, Ignore, dag, field, function, object_type


@object_type
class GleamSdk:
    sdk_source: dagger.Directory = field()

    def __init__(
        self,
        sdk_source: Annotated[
            dagger.Directory,
            DefaultPath(".."),
            Ignore(["build", "runtime/sdk", "runtime/.venv", "**/__pycache__"]),
        ],
    ):
        self.sdk_source = sdk_source

    async def _common(
        self, mod_source: dagger.ModuleSource, introspection_json: dagger.File
    ) -> tuple[dagger.Container, str, str]:
        name = await mod_source.module_name()
        subpath = await mod_source.source_subpath()
        # Both paths are engine-provided, but ensure neither escapes /src.
        relative = PurePosixPath(subpath or ".")
        if relative.is_absolute() or ".." in relative.parts:
            raise ValueError(f"Invalid module source subpath: {subpath!r}")
        workdir = str(PurePosixPath("/src") / relative)
        package = re.sub(r"[^a-z0-9]+", "_", re.sub(r"([a-z0-9])([A-Z])", r"\1_\2", name).lower()).strip("_")
        if not package or not package[0].isalpha():
            package = "module_" + package
        # Avoid colliding with the SDK package and reserve a fixed entrypoint.
        if package == "dagger":
            package = "dagger_module"
        object_name = "".join(word[:1].upper() + word[1:] for word in package.split("_"))
        base = (
            dag.container()
            .from_("ghcr.io/gleam-lang/gleam:v1.18.0-erlang")
            .with_exec(["sh", "-c", "if ! command -v python3 >/dev/null; then if command -v apk >/dev/null; then apk add --no-cache python3; else apt-get update && apt-get install -y --no-install-recommends python3 ca-certificates; fi; fi"])
            .with_directory("/src", mod_source.context_directory())
            .with_workdir(workdir)
            .with_directory("dagger_sdk", self.sdk_source, exclude=["build", "test", "examples", "runtime"])
            .with_file("/schema.json", introspection_json)
            .with_exec(["python3", "dagger_sdk/codegen/generate.py", "/schema.json", "--output", "dagger_sdk/src/dagger"])
        )
        entries = await base.directory(".").entries()
        if "gleam.toml" not in entries:
            template = self.sdk_source.directory("runtime/template")
            config = (await template.file("gleam.toml").contents()).replace("__PACKAGE__", package)
            source = (await template.file("main.gleam").contents()).replace("__OBJECT__", object_name)
            base = base.with_new_file("gleam.toml", config).with_new_file("src/dagger_main.gleam", source)
        else:
            # Existing projects opt in explicitly instead of having their files overwritten.
            config = await base.file("gleam.toml").contents()
            if tomllib.loads(config).get("dependencies", {}).get("dagger") != {"path": "dagger_sdk"}:
                raise ValueError('Existing gleam.toml must include dagger = { path = "dagger_sdk" } in [dependencies]')
        actual_package = tomllib.loads(config)["name"]
        if not re.fullmatch(r"[a-z][a-z0-9_]*", actual_package):
            raise ValueError("Invalid Gleam package name")
        # Shipment scripts always invoke the package's main module; this SDK
        # reserves dagger_main so existing applications can keep their main().
        launcher = (
            '#!/bin/sh\nset -eu\n'
            'BASE="$(dirname "$0")/build/erlang-shipment"\n'
            f'exec erl -pa "$BASE"/*/ebin -noshell -eval "\'{actual_package}@@main\':run(dagger_main)"\n'
        )
        base = base.with_new_file("dagger_sdk_entrypoint.sh", launcher)
        return base, subpath, workdir

    @function
    async def codegen(
        self, mod_source: dagger.ModuleSource, introspection_json: dagger.File
    ) -> dagger.GeneratedCode:
        container, subpath, _ = await self._common(mod_source, introspection_json)
        prefix = f"{subpath.rstrip('/')}/" if subpath and subpath != "." else ""
        return (
            dag.generated_code(container.directory("/src"))
            .with_vcs_generated_paths([prefix + "dagger_sdk/**", prefix + "dagger_sdk_entrypoint.sh"])
            .with_vcs_ignored_paths([prefix + "dagger_sdk", prefix + "dagger_sdk_entrypoint.sh", prefix + "build", prefix + "erl_crash.dump"])
        )

    @function
    async def module_runtime(
        self, mod_source: dagger.ModuleSource, introspection_json: dagger.File
    ) -> dagger.Container:
        container, _, workdir = await self._common(mod_source, introspection_json)
        return (
            container
            .with_exec(["gleam", "deps", "download"])
            .with_exec(["gleam", "build"])
            .with_exec(["gleam", "export", "erlang-shipment"])
            .with_entrypoint(["sh", f"{workdir}/dagger_sdk_entrypoint.sh"])
        )
