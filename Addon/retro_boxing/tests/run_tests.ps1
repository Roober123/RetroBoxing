$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '../../..')
try {
    & g++ -std=c++17 -IAddon/retro_boxing/src -Igodot-cpp/include -Igodot-cpp/gen/include -Igodot-cpp/gdextension Addon/retro_boxing/tests/pd_math_test.cpp godot-cpp/bin/libgodot-cpp.windows.template_debug.x86_64.a -static -o Addon/retro_boxing/bin/pd_math_test.exe
    if ($LASTEXITCODE -ne 0) { throw 'Math test compilation failed.' }
    & ./Addon/retro_boxing/bin/pd_math_test.exe
    if ($LASTEXITCODE -ne 0) { throw 'Math tests failed.' }
    Set-Content -LiteralPath .godot/pd-test.log -Value ''
    $runtime = Start-Process -FilePath (Get-Command godot).Source -ArgumentList '--headless --path . --log-file .godot/pd-test.log --script Addon/retro_boxing/tests/pd_runtime_test.gd --quit-after 1800' -WindowStyle Hidden -Wait -PassThru
    $runtimeOutput = Get-Content -LiteralPath .godot/pd-test.log -Raw
    Write-Host $runtimeOutput
    if ($runtime.ExitCode -ne 0 -or $runtimeOutput -notmatch 'PD runtime tests passed' -or $runtimeOutput -match 'SCRIPT ERROR:') {
        throw 'Runtime tests failed or timed out.'
    }
} finally {
    Pop-Location
}
