$ErrorActionPreference = 'Stop'
$tests = [ordered]@{
    'sim/run_rv32i.do'  = 'RV32I_TEST_PASSED'
    'sim/run_stage2.do' = 'PIPELINE_TEST_PASSED'
    'sim/run_stage3.do' = 'ICB_TEST_PASSED'
    'sim/run_stage4.do' = 'TRAP_TEST_PASSED'
    'sim/run_stage5.do' = 'SOC_TEST_PASSED'
    'sim/run_stage6.do' = 'RV32M_TEST_PASSED'
    'sim/run_gpu.do'    = 'GPU_TEST_PASSED'
    'sim/run_gpu_cpu.do'= 'GPU_CPU_TEST_PASSED'
}
foreach ($entry in $tests.GetEnumerator()) {
    Write-Host "==== $($entry.Key) ===="
    $output = & vsim -c -do $entry.Key 2>&1
    $output | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0 -or (($output -join "`n") -notmatch $entry.Value)) {
        throw "ModelSim regression failed or missing marker $($entry.Value): $($entry.Key)"
    }
}
Write-Host 'RVC_ALL_REGRESSIONS_PASSED'
