# Patches the generated Android/iOS projects for Keiyo Chat App:
# - Android: notification / foreground-service permissions, remoteMessaging service,
#   cleartext HTTP for the local Egg server, Gradle desugaring for local notifications.
# - iOS: background fetch capability, BGTaskScheduler identifier, ATS, plugin registrant.
#
# Run AFTER `flutter create --platforms=android,ios .`:
#   powershell -ExecutionPolicy Bypass -File tool/configure_platform.ps1
#
# The script is idempotent: existing permissions / keys / service tags are left alone.

param(
    [string]$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
)

$ErrorActionPreference = 'Stop'
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
$changed = New-Object System.Collections.Generic.List[string]

$manifestPath = Join-Path $ProjectRoot 'android/app/src/main/AndroidManifest.xml'
$plistPath = Join-Path $ProjectRoot 'ios/Runner/Info.plist'
$appDelegatePath = Join-Path $ProjectRoot 'ios/Runner/AppDelegate.swift'

if (-not (Test-Path $manifestPath) -or -not (Test-Path $plistPath)) {
    Write-Host 'Platform folders were not found.' -ForegroundColor Red
    Write-Host 'Run this first: flutter create --platforms=android,ios .'
    exit 1
}

# ---------------------------------------------------------------- Android
$manifest = [System.IO.File]::ReadAllText($manifestPath)

$permissions = @(
    'android.permission.INTERNET',
    'android.permission.POST_NOTIFICATIONS',
    'android.permission.FOREGROUND_SERVICE',
    'android.permission.FOREGROUND_SERVICE_REMOTE_MESSAGING',
    'android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS',
    'android.permission.WAKE_LOCK'
)

$missing = @()
foreach ($permission in $permissions) {
    if ($manifest -notmatch [regex]::Escape("android:name=`"$permission`"")) {
        $missing += $permission
    }
}
if ($missing.Count -gt 0) {
    $block = ($missing | ForEach-Object { "    <uses-permission android:name=`"$_`" />" }) -join "`r`n"
    $replacement = $block + "`r`n" + '$1<application'
    $manifest = [regex]::Replace($manifest, '(?m)^(\s*)<application\b', $replacement, 1)
    $changed.Add("Android permissions: $($missing -join ', ')")
}

if ($manifest -notmatch 'android:usesCleartextTraffic') {
    $manifest = [regex]::Replace(
        $manifest,
        '(?m)^(\s*)<application\b',
        "`$1<application`r`n        android:usesCleartextTraffic=`"true`"",
        1
    )
    $changed.Add('Android usesCleartextTraffic=true')
}

if ($manifest -notmatch 'com\.pravera\.flutter_foreground_task\.service\.ForegroundService') {
    $serviceBlock = @'
        <service
            android:name="com.pravera.flutter_foreground_task.service.ForegroundService"
            android:foregroundServiceType="remoteMessaging"
            android:exported="false" />
'@
    $replacement = $serviceBlock + "`r`n" + '$1</application>'
    $manifest = [regex]::Replace($manifest, '(?m)^(\s*)</application>', $replacement, 1)
    $changed.Add('Android foreground service (remoteMessaging)')
}

# FCM 下发时服务端指定了 channel_id，默认渠道必须与本地通知一致
if ($manifest -notmatch 'default_notification_channel_id') {
    $fcmMeta = @'
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_channel_id"
            android:value="keiyo_chat_messages" />
        <meta-data
            android:name="com.google.firebase.messaging.default_notification_icon"
            android:resource="@drawable/ic_stat_keiyo" />
'@
    $replacement = $fcmMeta + "`r`n" + '$1</application>'
    $manifest = [regex]::Replace($manifest, '(?m)^(\s*)</application>', $replacement, 1)
    $changed.Add('Android FCM default notification channel/icon')
}

[System.IO.File]::WriteAllText($manifestPath, $manifest, $utf8NoBom)

# ---------------------------------------------------------------- Android Gradle
# flutter_local_notifications 10+ 必需：core library desugaring + compileSdk >= 34
$gradlePath = Join-Path $ProjectRoot 'android/app/build.gradle'
$kotlinDsl = $false
if (-not (Test-Path $gradlePath)) {
    $gradlePath = Join-Path $ProjectRoot 'android/app/build.gradle.kts'
    $kotlinDsl = $true
}

if (Test-Path $gradlePath) {
    $gradle = [System.IO.File]::ReadAllText($gradlePath)
    $originalGradle = $gradle

    if ($kotlinDsl) {
        if ($gradle -notmatch 'isCoreLibraryDesugaringEnabled') {
            $gradle = [regex]::Replace(
                $gradle,
                '(?m)^([ \t]*)compileOptions\s*\{',
                '${0}' + "`r`n" + '${1}    isCoreLibraryDesugaringEnabled = true',
                1
            )
        }
        if ($gradle -notmatch 'desugar_jdk_libs') {
            $gradle = $gradle.TrimEnd() + "`r`n`r`ndependencies {`r`n    coreLibraryDesugaring(`"com.android.tools:desugar_jdk_libs:2.1.4`")`r`n}`r`n"
        }
    }
    else {
        if ($gradle -notmatch 'coreLibraryDesugaringEnabled') {
            $gradle = [regex]::Replace(
                $gradle,
                '(?m)^([ \t]*)compileOptions\s*\{',
                '${0}' + "`r`n" + '${1}    coreLibraryDesugaringEnabled true',
                1
            )
        }
        if ($gradle -notmatch 'desugar_jdk_libs') {
            $gradle = $gradle.TrimEnd() + "`r`n`r`ndependencies {`r`n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.4'`r`n}`r`n"
        }
    }

    # 模板里的 flutter.compileSdkVersion 不动，只把写死的低版本抬到 34
    $gradle = [regex]::Replace($gradle, '(?m)^([ \t]*compileSdk(?:Version)?\s*=?\s*)(\d+)', {
        param($m)
        $value = [int]$m.Groups[2].Value
        if ($value -ge 34) { return $m.Value }
        return $m.Groups[1].Value + '34'
    })

    # Firebase Android BoM 33 要求 minSdk >= 23（模板默认是 flutter.minSdkVersion = 21）
    $gradle = [regex]::Replace($gradle, '(?m)^([ \t]*minSdk\s*=\s*)flutter\.minSdkVersion', '${1}23')
    $gradle = [regex]::Replace($gradle, '(?m)^([ \t]*minSdkVersion\s+)flutter\.minSdkVersion', '${1}23')
    $gradle = [regex]::Replace($gradle, '(?m)^([ \t]*minSdk(?:Version)?\s*=?\s*)(\d+)', {
        param($m)
        $value = [int]$m.Groups[2].Value
        if ($value -ge 23) { return $m.Value }
        return $m.Groups[1].Value + '23'
    })

    if ($gradle -ne $originalGradle) {
        [System.IO.File]::WriteAllText($gradlePath, $gradle, $utf8NoBom)
        $changed.Add("Android desugaring / compileSdk ($(Split-Path $gradlePath -Leaf))")
    }
}
else {
    Write-Host 'android/app/build.gradle(.kts) not found; enable core library desugaring manually.' -ForegroundColor Yellow
}

# ---------------------------------------------------------------- Android Firebase (FCM)
# 只在 android/app/google-services.json 存在时应用 google-services 插件：
# 没有配置文件时仍能编译，只是运行时 Firebase 初始化失败，socket + 轮询继续工作。
$googleServicesJson = Join-Path $ProjectRoot 'android/app/google-services.json'
$rootGradlePath = Join-Path $ProjectRoot 'android/build.gradle'
$rootKotlinDsl = $false
if (-not (Test-Path $rootGradlePath)) {
    $rootGradlePath = Join-Path $ProjectRoot 'android/build.gradle.kts'
    $rootKotlinDsl = $true
}

if (Test-Path $googleServicesJson) {
    if (Test-Path $rootGradlePath) {
        $rootGradle = [System.IO.File]::ReadAllText($rootGradlePath)
        $originalRootGradle = $rootGradle
        if ($rootKotlinDsl) {
            if ($rootGradle -notmatch 'com\.google\.gms\.google-services') {
                $rootGradle = [regex]::Replace(
                    $rootGradle,
                    '(?m)^(plugins\s*\{)',
                    '${1}' + "`r`n    id(`"com.google.gms.google-services`") version `"4.4.2`" apply false",
                    1
                )
            }
        }
        elseif ($rootGradle -notmatch 'com\.google\.gms') {
            if ($rootGradle -match '(?s)buildscript\s*\{') {
                $rootGradle = [regex]::Replace(
                    $rootGradle,
                    '(?s)(buildscript\s*\{.*?dependencies\s*\{)',
                    '${1}' + "`r`n        classpath 'com.google.gms:google-services:4.4.2'",
                    1
                )
            }
            elseif ($rootGradle -match '(?m)^plugins\s*\{') {
                $rootGradle = [regex]::Replace(
                    $rootGradle,
                    '(?m)^(plugins\s*\{)',
                    '${1}' + "`r`n    id 'com.google.gms.google-services' version '4.4.2' apply false",
                    1
                )
            }
        }
        if ($rootGradle -ne $originalRootGradle) {
            [System.IO.File]::WriteAllText($rootGradlePath, $rootGradle, $utf8NoBom)
            $changed.Add("Android google-services classpath ($(Split-Path $rootGradlePath -Leaf))")
        }
    }

    if (Test-Path $gradlePath) {
        $appGradle = [System.IO.File]::ReadAllText($gradlePath)
        $originalAppGradle = $appGradle
        if ($kotlinDsl) {
            if ($appGradle -notmatch 'com\.google\.gms\.google-services') {
                $appGradle = [regex]::Replace(
                    $appGradle,
                    '(?m)^(plugins\s*\{)',
                    '${1}' + "`r`n    id(`"com.google.gms.google-services`")",
                    1
                )
            }
        }
        elseif ($appGradle -notmatch 'com\.google\.gms\.google-services') {
            $appGradle = $appGradle.TrimEnd() + "`r`n`r`napply plugin: 'com.google.gms.google-services'`r`n"
        }
        if ($appGradle -ne $originalAppGradle) {
            [System.IO.File]::WriteAllText($gradlePath, $appGradle, $utf8NoBom)
            $changed.Add("Android google-services plugin ($(Split-Path $gradlePath -Leaf))")
        }
    }
}
else {
    Write-Host 'android/app/google-services.json not found; FCM is disabled until you add it and re-run this script.' -ForegroundColor Yellow
}

# ---------------------------------------------------------------- iOS plist
$plist = [System.IO.File]::ReadAllText($plistPath)

function Add-PlistBlock([string]$Text, [string]$Marker, [string]$Block, [string]$Label) {
    if ($Text -match [regex]::Escape($Marker)) { return $Text }
    $replacement = $Block + "`r`n" + '$1'
    $script:result = [regex]::Replace($Text, '(?m)^(\s*</dict>\s*</plist>)', $replacement, 1)
    $script:changed.Add($Label)
    return $script:result
}

$plist = Add-PlistBlock $plist '<key>UIBackgroundModes</key>' @'
	<key>UIBackgroundModes</key>
	<array>
		<string>fetch</string>
	</array>
'@ 'iOS UIBackgroundModes=fetch'

# FCM 经 APNs 下发需要 remote-notification 后台模式（与 fetch 共存）
if ($plist -match '(?s)<key>UIBackgroundModes</key>\s*<array>(.*?)</array>') {
    $backgroundBlock = $Matches[0]
    if ($backgroundBlock -notmatch 'remote-notification') {
        $newBlock = $backgroundBlock -replace '</array>', "`t<string>remote-notification</string>`r`n`t</array>"
        $plist = $plist.Replace($backgroundBlock, $newBlock)
        $changed.Add('iOS UIBackgroundModes+=remote-notification')
    }
}

$plist = Add-PlistBlock $plist '<key>BGTaskSchedulerPermittedIdentifiers</key>' @'
	<key>BGTaskSchedulerPermittedIdentifiers</key>
	<array>
		<string>com.pravera.flutter_foreground_task.refresh</string>
	</array>
'@ 'iOS BGTaskSchedulerPermittedIdentifiers'

$plist = Add-PlistBlock $plist '<key>NSAppTransportSecurity</key>' @'
	<key>NSAppTransportSecurity</key>
	<dict>
		<key>NSAllowsArbitraryLoads</key>
		<true/>
	</dict>
'@ 'iOS ATS (arbitrary loads)'

[System.IO.File]::WriteAllText($plistPath, $plist, $utf8NoBom)

# ---------------------------------------------------------------- iOS Podfile
# Firebase iOS 11 要求 iOS 13+；Podfile 在 Windows 上通常由 flutter create 生成模板，也可能还不存在
$podfilePath = Join-Path $ProjectRoot 'ios/Podfile'
if (Test-Path $podfilePath) {
    $podfile = [System.IO.File]::ReadAllText($podfilePath)
    $originalPodfile = $podfile
    if ($podfile -match '(?m)^#?\s*platform :ios') {
        $podfile = [regex]::Replace($podfile, '(?m)^#?\s*platform :ios.*$', {
            param($m)
            $verMatch = [regex]::Match($m.Value, "'([\d.]+)'")
            if ($verMatch.Success) {
                $ver = [version]$verMatch.Groups[1].Value
                if ($ver -ge [version]'13.0') {
                    return "platform :ios, '$($verMatch.Groups[1].Value)'"
                }
            }
            return "platform :ios, '13.0'"
        }, 1)
    }
    else {
        $podfile = "platform :ios, '13.0'`r`n" + $podfile
    }
    if ($podfile -ne $originalPodfile) {
        [System.IO.File]::WriteAllText($podfilePath, $podfile, $utf8NoBom)
        $changed.Add('iOS Podfile platform 13.0')
    }
}
else {
    Write-Host 'ios/Podfile not found; on macOS run `flutter pub get` and set platform :ios, 13.0.' -ForegroundColor Yellow
}

# ---------------------------------------------------------------- iOS AppDelegate
if (Test-Path $appDelegatePath) {
    $appDelegate = [System.IO.File]::ReadAllText($appDelegatePath)
    $original = $appDelegate

    if ($appDelegate -notmatch 'import flutter_foreground_task') {
        if ($appDelegate -match '(?m)^import Flutter\r?$') {
            $appDelegate = [regex]::Replace(
                $appDelegate,
                '(?m)^import Flutter\r?$',
                "import Flutter`r`nimport flutter_foreground_task`r`nimport UserNotifications",
                1
            )
        }
    }

    if ($appDelegate -notmatch 'SwiftFlutterForegroundTaskPlugin') {
        # 插在 GeneratedPluginRegistrant.register 之后，缩进跟模板保持一致
        $registerPattern = '(?m)^([ \t]*)GeneratedPluginRegistrant\.register\(with: self\)[ \t]*\r?\n'
        $registerMatch = [regex]::Match($appDelegate, $registerPattern)
        if ($registerMatch.Success) {
            $indent = $registerMatch.Groups[1].Value
            $inject = @"
${indent}SwiftFlutterForegroundTaskPlugin.setPluginRegistrantCallback { registry in
${indent}  GeneratedPluginRegistrant.register(with: registry)
${indent}}
${indent}if #available(iOS 10.0, *) {
${indent}  UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
${indent}}

"@
            $appDelegate = [regex]::Replace(
                $appDelegate,
                $registerPattern,
                { param($m) $m.Value + $inject },
                1
            )
        }
    }

    # Firebase iOS 需要在启动时读取 GoogleService-Info.plist；没放配置就不注入，避免启动崩溃
    $googleServicesPlist = Join-Path $ProjectRoot 'ios/Runner/GoogleService-Info.plist'
    if (Test-Path $googleServicesPlist) {
        if ($appDelegate -notmatch 'import FirebaseCore') {
            if ($appDelegate -match '(?m)^import Flutter\r?$') {
                $appDelegate = [regex]::Replace(
                    $appDelegate,
                    '(?m)^import Flutter\r?$',
                    "import Flutter`r`nimport FirebaseCore",
                    1
                )
            }
        }
        if ($appDelegate -notmatch 'FirebaseApp\.configure\(\)') {
            $appDelegate = [regex]::Replace(
                $appDelegate,
                '(?m)^([ \t]*)GeneratedPluginRegistrant\.register\(with: self\)',
                { param($m) $m.Groups[1].Value + "FirebaseApp.configure()`r`n" + $m.Value },
                1
            )
        }
    }

    if ($appDelegate -ne $original) {
        [System.IO.File]::WriteAllText($appDelegatePath, $appDelegate, $utf8NoBom)
        $changed.Add('iOS AppDelegate registrant / notification delegate')
    }
}
else {
    Write-Host 'ios/Runner/AppDelegate.swift not found; add the plugin registrant manually (see README).' -ForegroundColor Yellow
}

# ---------------------------------------------------------------- report
if (-not (Test-Path (Join-Path $ProjectRoot 'ios/Runner/GoogleService-Info.plist'))) {
    # iOS 推送直连 APNs、不经 Firebase，所以缺这个文件不影响推送；仅当你要在 iOS 上用其他 Firebase 产品时才需要它
    Write-Host 'ios/Runner/GoogleService-Info.plist not found (only needed if you use Firebase products on iOS; iOS push goes APNs directly).' -ForegroundColor Yellow
}
Write-Host 'iOS reminder: enable the Push Notifications capability in Xcode (Signing & Capabilities) before archiving.' -ForegroundColor Yellow
if (-not (Test-Path $googleServicesJson)) {
    Write-Host 'Android reminder: place google-services.json in android/app and re-run this script.' -ForegroundColor Yellow
}

if ($changed.Count -eq 0) {
    Write-Host 'Platform configuration is already up to date.'
}
else {
    Write-Host 'Platform configuration updated:'
    foreach ($item in $changed) { Write-Host "  - $item" }
}
