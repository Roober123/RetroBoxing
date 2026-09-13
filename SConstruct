#!/usr/bin/env python

from pathlib import Path
import sys


# Keep compiled objects and the godot-cpp archive reusable across clean builds and
# build directories. MD5 signatures make the cache independent of timestamps.
cache_dir = Path(Dir("#").abspath) / ".scons-cache"
CacheDir(str(cache_dir))
Decider("MD5")
SetOption("implicit_cache", True)

# MSYS2 may export MINGW_PREFIX as the directory containing its internal
# toolchain. godot-cpp treats that value as a cross-compiler root and appends
# another `bin/<target>-w64-mingw32-`, producing an invalid executable path.
# For native Windows builds, prefer MinGW from PATH unless the caller explicitly
# supplies `mingw_prefix=...` on the SCons command line.
if sys.platform == "win32" and "mingw_prefix" not in ARGUMENTS:
    ARGUMENTS["mingw_prefix"] = ""

# These are project defaults and can still be overridden on the command line,
# for example: scons target=template_release use_hot_reload=no
env = Environment(
    tools=["default"],
    PLATFORM="",
    use_mingw=True,
    use_hot_reload=True,
)

env = SConscript(
    "godot-cpp/SConstruct",
    exports={
        "env": env,
        "api_version": "4.7",
    },
)

# godot-cpp deliberately marks its final archive as non-cacheable upstream.
# This project opts it back into CacheDir; its compiled object files are cached
# as well, so an identical configuration does not rebuild the bindings/library.
for linked_library in env["LIBS"]:
    if Path(str(linked_library)).name.startswith("libgodot-cpp"):
        linked_library.set_nocache(False)

env.AppendUnique(CPPPATH=[Dir("#/Addon/retro_boxing/src")])
extension_sources = Glob("Addon/retro_boxing/src/*.cpp")

extension = env.SharedLibrary(
    target="Addon/retro_boxing/bin/retro_boxing{}{}".format(
        env["suffix"], env["SHLIBSUFFIX"]
    ),
    source=extension_sources,
)

# Never restore the loaded extension DLL from cache: hot reload expects a newly
# linked file while Godot keeps uniquely named shadow copies of loaded DLLs.
env.NoCache(extension)
Default(extension)
