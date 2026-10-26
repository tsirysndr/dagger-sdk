// Dagger's custom-SDK adapter. User modules and their entrypoint are PureScript.
package main

import (
	"context"
	"fmt"
	"path"

	"purescript-sdk/internal/dagger"
)

type PurescriptSdk struct {
	Source *dagger.Directory
}

func New(
	// PureScript SDK sources, relative to the SDK's dagger.json.
	// +defaultPath="."
	// +ignore=[".spago", "output", "node_modules", "runtime/internal", "runtime/dagger.gen.go", "examples"]
	source *dagger.Directory,
) *PurescriptSdk {
	return &PurescriptSdk{Source: source}
}

func (m *PurescriptSdk) Codegen(ctx context.Context, modSource *dagger.ModuleSource, introspectionJSON *dagger.File) (*dagger.GeneratedCode, error) {
	ctr, subpath, err := m.prepare(ctx, modSource, introspectionJSON)
	if err != nil {
		return nil, err
	}
	return dag.GeneratedCode(ctr.Directory("/src").
		WithoutDirectory(path.Join(subpath, "output")).
		WithoutDirectory(path.Join(subpath, ".spago")).
		WithoutDirectory(path.Join(subpath, "node_modules"))).
		WithVCSGeneratedPaths([]string{"dagger-sdk/**"}).
		WithVCSIgnoredPaths([]string{"dagger-sdk", ".spago", "output", "node_modules"}), nil
}

func (m *PurescriptSdk) ModuleRuntime(ctx context.Context, modSource *dagger.ModuleSource, introspectionJSON *dagger.File) (*dagger.Container, error) {
	ctr, _, err := m.prepare(ctx, modSource, introspectionJSON)
	if err != nil {
		return nil, err
	}
	return ctr.WithExec([]string{"spago", "build"}).
		WithEntrypoint([]string{"node", "--input-type=module", "-e", "import('./output/Main/index.js').then(m => m.main()).catch(e => { console.error(e); process.exitCode = 1; })"}), nil
}

func (m *PurescriptSdk) prepare(ctx context.Context, modSource *dagger.ModuleSource, introspectionJSON *dagger.File) (*dagger.Container, string, error) {
	subpath, err := modSource.SourceSubpath(ctx)
	if err != nil {
		return nil, "", fmt.Errorf("module source path: %w", err)
	}
	name, err := modSource.ModuleOriginalName(ctx)
	if err != nil {
		return nil, "", fmt.Errorf("module name: %w", err)
	}
	ctr := dag.Container().From("node:22-bookworm-slim").
		WithExec([]string{"sh", "-c", "apt-get update && apt-get install -y --no-install-recommends ca-certificates git libtinfo6 && rm -rf /var/lib/apt/lists/*"}).
		WithExec([]string{"npm", "install", "--global", "purescript@0.15.16", "spago@1.0.5"}).
		WithDirectory("/sdk", m.Source).
		WithFile("/schema.json", introspectionJSON).
		WithExec([]string{"node", "/sdk/scripts/generate.mjs", "/schema.json"})
	// Keep the generated package's source and manifest, without its workspace or tests.
	sdk := ctr.Directory("/sdk").WithoutDirectory("runtime").WithoutDirectory("schema").
		WithoutDirectory("test").WithoutDirectory(".spago").WithoutDirectory("output").
		WithoutDirectory("node_modules").WithoutFile("spago.lock")
	workdir := path.Join("/src", subpath)
	contextDir := modSource.ContextDirectory().
		WithoutDirectory(path.Join(subpath, "dagger-sdk")).
		WithoutDirectory(path.Join(subpath, ".spago")).
		WithoutDirectory(path.Join(subpath, "output")).
		WithoutDirectory(path.Join(subpath, "node_modules"))
	ctr = ctr.WithDirectory("/src", contextDir).
		WithDirectory(path.Join(workdir, "dagger-sdk"), sdk).
		WithWorkdir(workdir).
		WithExec([]string{"node", "/sdk/scripts/init-module.mjs", name}).
		WithMountedCache("/root/.cache/spago-nodejs", dag.CacheVolume("purescript-spago-0.15.16"))
	return ctr, subpath, nil
}
