$ErrorActionPreference = 'Stop'
Push-Location (Join-Path $PSScriptRoot '../../..')
try {
    & g++ -std=c++17 -IAddon/retro_boxing/src -Igodot-cpp/include -Igodot-cpp/gen/include -Igodot-cpp/gdextension Addon/retro_boxing/tests/pd_math_test.cpp godot-cpp/bin/libgodot-cpp.windows.template_debug.x86_64.a -static -o Addon/retro_boxing/bin/pd_math_test.exe
    if ($LASTEXITCODE -ne 0) { throw 'Math test compilation failed.' }
    & ./Addon/retro_boxing/bin/pd_math_test.exe
    if ($LASTEXITCODE -ne 0) { throw 'Math tests failed.' }
    $api = Start-Process -FilePath (Get-Command godot).Source -ArgumentList '--headless --path . --log-file .godot/profile-api.log --script Addon/retro_boxing/tests/profile_api_test.gd --quit-after 10' -WindowStyle Hidden -Wait -PassThru
    $apiOutput = Get-Content -LiteralPath .godot/profile-api.log -Raw
    Write-Host $apiOutput
    if ($api.ExitCode -ne 0 -or $apiOutput -notmatch 'PD profile API tests passed' -or $apiOutput -match 'SCRIPT ERROR:') {
        throw 'Profile API tests failed.'
    }
    Set-Content -LiteralPath .godot/pd-test.log -Value ''
    $runtime = Start-Process -FilePath (Get-Command godot).Source -ArgumentList '--headless --path . --log-file .godot/pd-test.log --script Addon/retro_boxing/tests/pd_runtime_test.gd --quit-after 9000' -WindowStyle Hidden -Wait -PassThru
    $runtimeOutput = Get-Content -LiteralPath .godot/pd-test.log -Raw
    Write-Host $runtimeOutput
    if ($runtime.ExitCode -ne 0 -or $runtimeOutput -notmatch 'PD runtime tests passed' -or $runtimeOutput -match 'SCRIPT ERROR:') {
        throw 'Runtime tests failed or timed out.'
    }
    Set-Content -LiteralPath .godot/balance-test.log -Value ''
    $balance = Start-Process -FilePath (Get-Command godot).Source -ArgumentList '--headless --path . --log-file .godot/balance-test.log --script Addon/retro_boxing/tests/balance_preparation_test.gd --quit-after 9000' -WindowStyle Hidden -Wait -PassThru
    $balanceOutput = Get-Content -LiteralPath .godot/balance-test.log -Raw
    Write-Host $balanceOutput
    if ($balance.ExitCode -ne 0 -or $balanceOutput -notmatch 'Balance preparation tests passed' -or $balanceOutput -match 'SCRIPT ERROR:') {
        throw 'Balance preparation tests failed or timed out.'
    }
    $multiArena = Start-Process -FilePath (Get-Command godot).Source -ArgumentList '--headless --path . --log-file .godot/multi-arena-test.log --script Addon/retro_boxing/tests/multi_arena_training_test.gd --quit-after 9000' -WindowStyle Hidden -Wait -PassThru
    $multiArenaOutput = Get-Content -LiteralPath .godot/multi-arena-test.log -Raw
    Write-Host $multiArenaOutput
    if ($multiArena.ExitCode -ne 0 -or $multiArenaOutput -notmatch 'Multi-arena training tests passed' -or $multiArenaOutput -match 'SCRIPT ERROR:') {
        throw 'Multi-arena training tests failed or timed out.'
    }
    $transition = Start-Process -FilePath (Get-Command godot).Source -ArgumentList '--headless --path . --log-file .godot/training-transition-test.log --script Addon/retro_boxing/tests/training_transition_test.gd --quit-after 9000' -WindowStyle Hidden -Wait -PassThru
    $transitionOutput = Get-Content -LiteralPath .godot/training-transition-test.log -Raw
    Write-Host $transitionOutput
    if ($transition.ExitCode -ne 0 -or $transitionOutput -notmatch 'Training transition tests passed' -or $transitionOutput -match 'SCRIPT ERROR:') {
        throw 'Training transition tests failed or timed out.'
    }
    $stress = Start-Process -FilePath (Get-Command godot).Source -ArgumentList '--headless --path . --log-file .godot/rl-stress-test.log --script Addon/retro_boxing/tests/rl_environment_stress_test.gd --quit-after 9000' -WindowStyle Hidden -Wait -PassThru
    $stressOutput = Get-Content -LiteralPath .godot/rl-stress-test.log -Raw
    Write-Host $stressOutput
    if ($stress.ExitCode -ne 0 -or $stressOutput -notmatch 'RL environment stress tests passed' -or $stressOutput -match 'SCRIPT ERROR:') {
        throw 'RL environment stress tests failed or timed out.'
    }
    $actions = Start-Process -FilePath (Get-Command godot).Source -ArgumentList '--headless --path . --log-file .godot/balance-action-test.log --script Addon/retro_boxing/tests/balance_action_runtime_test.gd --quit-after 9000' -WindowStyle Hidden -Wait -PassThru
    $actionOutput = Get-Content -LiteralPath .godot/balance-action-test.log -Raw
    Write-Host $actionOutput
    if ($actions.ExitCode -ne 0 -or $actionOutput -notmatch 'Balance action runtime tests passed' -or $actionOutput -match 'SCRIPT ERROR:') {
        throw 'Balance action runtime tests failed or timed out.'
    }
} finally {
    Pop-Location
}
