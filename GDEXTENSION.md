# GDExtension development

The C++ starter extension lives in `Addon/retro_boxing`. Its example node is
registered as `RetroBoxingExample` and exposes `get_greeting()` to Godot.

## Clone

Clone this repository with its `godot-cpp` submodule:

```powershell
git clone --recurse-submodules <repository-url>
```

For an existing clone:

```powershell
git submodule update --init --recursive
```

## Build

From the project root, run:

```powershell
scons
```

The defaults are a 64-bit Windows debug build, MinGW (`use_mingw=yes`), Godot
4.7 API bindings, and hot-reload bookkeeping (`use_hot_reload=yes`). Build a
release library with:

```powershell
scons target=template_release
```

On native Windows, the build uses `g++` from `PATH`. This intentionally ignores
MSYS2's inherited `MINGW_PREFIX`, which has a different meaning than the
cross-compiler prefix expected by `godot-cpp`. An actual cross-toolchain root can
still be selected explicitly with `mingw_prefix=<path>`.

SCons stores reusable build artifacts in `.scons-cache`. Its signature database
also prevents unchanged `godot-cpp` inputs from rebuilding during normal
incremental builds. Both are local generated data and are ignored by Git.

The extension manifest has `reloadable = true`. Hot reload still requires every
live instance of an extension class to be freed before Godot can unload the old
library.
