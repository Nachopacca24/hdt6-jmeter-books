# Corre plan.jmx sin interfaz a cada nivel, con el API ya levantado (uv run api.py).
# Deja el reporte en corridas/<usuarios>/reporte, copia statistics.json a
# resultados/<usuarios>/ y mide el CPU del API y de JMeter en corridas/<usuarios>/cpu.json.
param(
    [int[]]$Niveles = @(10, 50, 100, 200, 500),
    [string]$JMeter = "$env:USERPROFILE\tools\apache-jmeter-5.6.3"
)
$ErrorActionPreference = "Stop"
$cores = [Environment]::ProcessorCount

foreach ($u in $Niveles) {
    $dir = "corridas\$u"
    if (Test-Path $dir) { Remove-Item -Recurse -Force $dir }
    New-Item -ItemType Directory -Force $dir, "resultados\$u" | Out-Null

    Invoke-RestMethod -Method Post http://127.0.0.1:8000/reset | Out-Null
    $api = Get-Process -Id (Get-NetTCPConnection -LocalPort 8000 -State Listen).OwningProcess

    $args = "-n -t plan.jmx -Jusers=$u -Jrampup=10 -Jhold=60 -l $dir\resultados.jtl -j $dir\jmeter.log -e -o $dir\reporte"
    $bat = Start-Process -FilePath "$JMeter\bin\jmeter.bat" -ArgumentList $args -NoNewWindow -PassThru
    Start-Sleep 3
    $java = Get-CimInstance Win32_Process -Filter "Name='java.exe'" |
        Where-Object { $_.CommandLine -like "*ApacheJMeter.jar*" -and $_.CommandLine -like "*plan.jmx*" } |
        ForEach-Object { Get-Process -Id $_.ProcessId }

    # Una muestra por segundo: porcentaje de un núcleo que usó cada proceso.
    $muestras = @()
    $prevApi = $api.TotalProcessorTime.TotalSeconds
    $prevJava = $java.TotalProcessorTime.TotalSeconds
    $prevT = Get-Date
    while (-not $java.HasExited) {
        Start-Sleep 1
        $api.Refresh(); $java.Refresh()
        if ($java.HasExited) { break }
        $t = Get-Date
        $dt = ($t - $prevT).TotalSeconds
        $a = $api.TotalProcessorTime.TotalSeconds
        $j = $java.TotalProcessorTime.TotalSeconds
        $muestras += [pscustomobject]@{ api = 100 * ($a - $prevApi) / $dt; jmeter = 100 * ($j - $prevJava) / $dt }
        $prevApi = $a; $prevJava = $j; $prevT = $t
    }
    $bat.WaitForExit()

    # Promedio de la parte sostenida: se quitan los primeros 10 s de ramp-up y el cierre.
    $sost = $muestras | Select-Object -Skip 10 | Select-Object -SkipLast 3
    [pscustomobject]@{
        usuarios        = $u
        nucleos         = $cores
        api_prom_pct    = [math]::Round(($sost | Measure-Object api -Average).Average, 1)
        api_max_pct     = [math]::Round(($sost | Measure-Object api -Maximum).Maximum, 1)
        jmeter_prom_pct = [math]::Round(($sost | Measure-Object jmeter -Average).Average, 1)
        jmeter_max_pct  = [math]::Round(($sost | Measure-Object jmeter -Maximum).Maximum, 1)
    } | ConvertTo-Json | Set-Content -Encoding utf8 "$dir\cpu.json"

    Copy-Item "$dir\reporte\statistics.json" "resultados\$u\statistics.json"
    python gate.py "$dir\reporte"
    "$u usuarios: puerta = $LASTEXITCODE" | Tee-Object -Append corridas\puerta.txt
}
