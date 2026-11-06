# 在本机把 Keiyo Chat App 构建/运行到 Android 真机。
#
#   powershell -ExecutionPolicy Bypass -File tool/run_android.ps1
#   powershell -ExecutionPolicy Bypass -File tool/run_android.ps1 -BuildOnly
#
# 本机踩过的两个坑，脚本里已经绕开：
# 1. Gradle daemon 启动时 FileLockContentionHandler 绑定本地端口失败
#    （BindException: Address already in use），必须走单次进程。
# 2. 插件的 Kotlin 源码在 C 盘 pub cache、项目在 D 盘，增量编译缓存会报
#    "this and base files have different roots"（已在 android/gradle.properties
#    里关掉 kotlin.incremental）。

param(
    # 留空表示交给 flutter 自己挑（只连一台设备时最省事）
    [string]$DeviceId = '',
    [string]$Flutter = 'D:\work\saishi\flutter\flutter\bin\flutter.bat',
    [string]$JavaHome = 'C:\Users\98188\.jdks\corretto-17.0.16',
    [switch]$BuildOnly
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path

if (-not (Test-Path $Flutter)) {
    $cmd = Get-Command flutter -ErrorAction SilentlyContinue
    if ($cmd) { $Flutter = $cmd.Source }
    else { throw "flutter not found: $Flutter" }
}

if ((Test-Path $JavaHome) -and (Test-Path (Join-Path $JavaHome 'bin/java.exe'))) {
    $env:JAVA_HOME = $JavaHome
    $env:PATH = (Join-Path $JavaHome 'bin') + ';' + $env:PATH
}

# 本机必须：否则 Gradle daemon 起不来
$env:GRADLE_OPTS = '-Dorg.gradle.daemon=false'

Push-Location $root
try {
    if ($BuildOnly) {
        & $Flutter build apk --debug
    } elseif ($DeviceId) {
        & $Flutter run -d $DeviceId
    } else {
        & $Flutter run
    }
} finally {
    Pop-Location
}
