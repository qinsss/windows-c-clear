Set-StrictMode -Version Latest

function Format-ByteSize {
    param([long]$Bytes)
    if ($Bytes -ge 1TB) { return ('{0:N2} TB' -f ($Bytes / 1TB)) }
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f $Bytes)
}

function Test-IsReparsePoint {
    param([System.IO.FileSystemInfo]$Item)
    return (($Item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-SafeFolderStats {
    param(
        [Parameter(Mandatory)][string]$Path,
        [int]$MaxFiles = 0,
        [int]$MaxMilliseconds = 0
    )

    [long]$bytes = 0
    [long]$files = 0
    $truncated = $false
    $watch = [System.Diagnostics.Stopwatch]::StartNew()
    $stack = [System.Collections.Generic.Stack[string]]::new()
    $stack.Push($Path)

    while ($stack.Count -gt 0 -and -not $truncated) {
        $current = $stack.Pop()
        $children = @(Get-ChildItem -LiteralPath $current -Force -ErrorAction SilentlyContinue)
        foreach ($child in $children) {
            if (($MaxMilliseconds -gt 0 -and $watch.ElapsedMilliseconds -ge $MaxMilliseconds) -or
                ($MaxFiles -gt 0 -and $files -ge $MaxFiles)) {
                $truncated = $true
                break
            }
            if (Test-IsReparsePoint $child) { continue }
            if ($child.PSIsContainer) {
                $stack.Push($child.FullName)
            } else {
                $bytes += [long]$child.Length
                $files++
            }
        }
    }

    $watch.Stop()

    [pscustomobject]@{ Bytes = $bytes; FileCount = $files; Truncated = $truncated }
}

function New-CleanerItem {
    param(
        [string]$Id,
        [string]$Name,
        [string]$Path,
        [string]$Purpose,
        [ValidateSet('建议清理','谨慎清理','手动审查')][string]$Level,
        [string]$Impact,
        [ValidateSet('Contents','File','PatternFiles')][string]$DeleteMode = 'Contents',
        [string[]]$Patterns = @(),
        [bool]$DefaultSelected = $false
    )

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $resolved = (Resolve-Path -LiteralPath $Path -ErrorAction SilentlyContinue).Path
    if (-not $resolved) { return $null }

    $rootItem = Get-Item -LiteralPath $resolved -Force -ErrorAction SilentlyContinue
    if (-not $rootItem -or (Test-IsReparsePoint $rootItem)) { return $null }

    if ($DeleteMode -eq 'File') {
        $file = $rootItem
        if (-not $file -or $file.PSIsContainer -or (Test-IsReparsePoint $file)) { return $null }
        $stats = [pscustomobject]@{ Bytes = [long]$file.Length; FileCount = 1 }
    } elseif ($DeleteMode -eq 'PatternFiles') {
        if (-not $rootItem.PSIsContainer -or $Patterns.Count -eq 0) { return $null }
        $matchedFiles = @(Get-ChildItem -LiteralPath $resolved -File -Force -ErrorAction SilentlyContinue | Where-Object {
            $matched = $false
            foreach ($pattern in $Patterns) { if ($_.Name -like $pattern) { $matched = $true; break } }
            $matched -and -not (Test-IsReparsePoint $_)
        })
        [long]$matchedBytes = 0
        foreach ($matchedFile in $matchedFiles) { $matchedBytes += [long]$matchedFile.Length }
        $stats = [pscustomobject]@{ Bytes = $matchedBytes; FileCount = $matchedFiles.Count }
    } else {
        $stats = Get-SafeFolderStats -Path $resolved
    }

    [pscustomobject]@{
        Selected = $DefaultSelected
        Id = $Id
        Name = $Name
        Kind = '用户级数据'
        Source = 'Cleanup'
        Level = $Level
        Path = $resolved
        Purpose = $Purpose
        Impact = $Impact
        Bytes = [long]$stats.Bytes
        Size = Format-ByteSize $stats.Bytes
        FileCount = [long]$stats.FileCount
        DeleteMode = $DeleteMode
        Patterns = @($Patterns)
    }
}

function Get-ProfileCacheFolders {
    param([string]$BrowserRoot, [string]$BrowserName)
    if (-not (Test-Path -LiteralPath $BrowserRoot)) { return @() }

    $results = @()
    $profiles = @(Get-ChildItem -LiteralPath $BrowserRoot -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq 'Default' -or $_.Name -like 'Profile *' })
    foreach ($profile in $profiles) {
        foreach ($cacheName in @('Cache\Cache_Data', 'Code Cache', 'GPUCache')) {
            $cachePath = Join-Path $profile.FullName $cacheName
            $safeId = ($BrowserName + '_' + $profile.Name + '_' + $cacheName) -replace '[^a-zA-Z0-9_]', '_'
            $item = New-CleanerItem -Id $safeId -Name "$BrowserName 缓存（$($profile.Name) / $cacheName）" `
                -Path $cachePath -Purpose '网页图片、脚本和图形缓存，用于加快再次访问。' -Level '谨慎清理' `
                -Impact '不会删除书签和密码；下次浏览时会重新下载，首次打开页面可能稍慢。请先关闭浏览器。'
            if ($item) { $results += $item }
        }
    }
    return $results
}

function Get-DiscoveredAppDataCaches {
    param([string[]]$ExistingPaths = @())

    $results = @()
    $roots = @(
        [Environment]::GetFolderPath('LocalApplicationData'),
        [Environment]::GetFolderPath('ApplicationData'),
        (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'AppData\LocalLow')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique

    $cacheNames = @('Cache','Caches','Code Cache','GPUCache','ShaderCache','DawnCache','LocalCache','TempState','CachedData','Logs','Crashpad','CrashDumps','Temp')
    $known = [System.Collections.Generic.List[string]]::new()
    foreach ($path in $ExistingPaths) { $known.Add([System.IO.Path]::GetFullPath($path).TrimEnd('\')) }

    foreach ($root in $roots) {
        $rootPath = [System.IO.Path]::GetFullPath($root).TrimEnd('\')
        $stack = [System.Collections.Generic.Stack[object]]::new()
        $stack.Push([pscustomobject]@{ Path=$rootPath; Depth=0 })
        while ($stack.Count -gt 0) {
            $current = $stack.Pop()
            if ($current.Depth -ge 5) { continue }
            $directories = @(Get-ChildItem -LiteralPath $current.Path -Directory -Force -ErrorAction SilentlyContinue)
            foreach ($directory in $directories) {
                if (Test-IsReparsePoint $directory) { continue }
                $full = $directory.FullName.TrimEnd('\')
                $relative = $full.Substring($rootPath.Length).TrimStart('\')
                if ($relative -like 'Microsoft\Windows*') { continue }

                $overlaps = $false
                foreach ($existing in $known) {
                    if ($full.Equals($existing, [System.StringComparison]::OrdinalIgnoreCase) -or
                        $full.StartsWith($existing + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
                        $existing.StartsWith($full + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $overlaps = $true; break
                    }
                }

                if ($cacheNames -contains $directory.Name) {
                    if (-not $overlaps) {
                        $isLog = $directory.Name -eq 'Logs'
                        $purpose = if ($isLog) { '应用运行日志，用于诊断错误和使用情况。' } else { '应用生成的缓存、临时数据或崩溃诊断文件。' }
                        $impact = if ($isLog) { '删除后无法查看旧日志；不影响应用主体。' } else { '应用可能需要重新生成或下载这些数据，首次启动可能变慢，也可能需要重新登录。' }
                        $item = New-CleanerItem -Id ('appdata_' + $full.GetHashCode()) -Name ('应用缓存：' + $relative) `
                            -Path $full -Purpose $purpose -Level '谨慎清理' -Impact $impact
                        if ($item -and $item.Bytes -gt 0) {
                            $results += $item
                            $known.Add($full)
                        }
                    }
                    # A recognized cache is represented as one unit; do not discover nested duplicates.
                    continue
                }
                if (-not $overlaps) { $stack.Push([pscustomobject]@{ Path=$full; Depth=($current.Depth + 1) }) }
            }
        }
    }
    return @($results | Sort-Object Bytes -Descending | Select-Object -First 100)
}

function ConvertFrom-AppDataInventoryJson {
    param([Parameter(Mandatory)][string]$Json)

    $parsedItems = ConvertFrom-Json -InputObject $Json
    $count = 0
    foreach ($parsedItem in $parsedItems) {
        if ($null -eq $parsedItem) { continue }
        if ($null -eq $parsedItem.PSObject.Properties['Bytes']) {
            throw '精确扫描结果中存在缺少 Bytes 属性的项目。'
        }
        $count++
        Write-Output $parsedItem
    }
    if ($count -eq 0) { throw '精确扫描没有返回可用的 AppData 统计项目。' }
}

function Measure-CleanerItemsBytes {
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Items = @())
    [long]$total = 0
    foreach ($item in $Items) {
        if ($null -ne $item -and $null -ne $item.PSObject.Properties['Bytes']) {
            $total += [long]$item.Bytes
        }
    }
    return $total
}

function Get-AppDataUsageInventory {
    param(
        [switch]$Exact,
        [string]$ProgressPath
    )

    $roots = @(
        [pscustomobject]@{ Scope='Local'; Path=[Environment]::GetFolderPath('LocalApplicationData') },
        [pscustomobject]@{ Scope='Roaming'; Path=[Environment]::GetFolderPath('ApplicationData') },
        [pscustomobject]@{ Scope='LocalLow'; Path=(Join-Path ([Environment]::GetFolderPath('UserProfile')) 'AppData\LocalLow') }
    )
    $results = @()
    $totalDirectories = 0
    if ($ProgressPath) {
        foreach ($progressRoot in $roots) {
            if ($progressRoot.Path -and (Test-Path -LiteralPath $progressRoot.Path)) {
                $totalDirectories += @(Get-ChildItem -LiteralPath $progressRoot.Path -Directory -Force -ErrorAction SilentlyContinue |
                    Where-Object { -not (Test-IsReparsePoint $_) }).Count
            }
        }
    }
    $completedDirectories = 0
    foreach ($root in $roots) {
        if (-not $root.Path -or -not (Test-Path -LiteralPath $root.Path)) { continue }
        foreach ($directory in @(Get-ChildItem -LiteralPath $root.Path -Directory -Force -ErrorAction SilentlyContinue)) {
            if (Test-IsReparsePoint $directory) { continue }
            if ($ProgressPath) {
                $progress = [pscustomobject]@{ Completed=$completedDirectories; Total=$totalDirectories; Current=$directory.Name; Scope=$root.Scope }
                [System.IO.File]::WriteAllText($ProgressPath, ($progress | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
            }
            if ($Exact) {
                $stats = Get-SafeFolderStats -Path $directory.FullName
            } else {
                # Bound work per application so a large package store cannot freeze startup.
                $stats = Get-SafeFolderStats -Path $directory.FullName -MaxFiles 3000 -MaxMilliseconds 250
            }
            $purpose = switch -Regex ($directory.Name) {
                '^Packages$' { 'Microsoft Store 应用的配置、缓存和本地文件。'; break }
                '^Microsoft$' { 'Windows 与 Microsoft 应用的当前用户配置和数据。'; break }
                '^(Google|Mozilla|BraveSoftware|Vivaldi)$' { '浏览器程序数据、用户配置和缓存；并不等同于纯缓存。'; break }
                '^(Programs|Apps)$' { '安装在当前用户范围内的应用程序文件。'; break }
                default { '该应用或厂商保存在当前用户配置文件中的私有数据。' }
            }
            $results += [pscustomobject]@{
                Selected=$false; Name=$directory.Name; Scope=$root.Scope; Path=$directory.FullName
                Kind='用户级数据'; Source='AppData'; Level='高风险'; DeleteMode='Contents'; Patterns=@()
                Purpose=$purpose; Bytes=[long]$stats.Bytes
                Size=$(if ($stats.Truncated) { '≥ ' + (Format-ByteSize $stats.Bytes) } else { Format-ByteSize $stats.Bytes })
                FileCount=$(if ($stats.Truncated) { "≥ $($stats.FileCount)" } else { [string]$stats.FileCount })
                Advice=$(if ($stats.Truncated) { '快速估算值；删除可能丢失登录、配置或本地数据，务必先双击核对。' } else { '删除可能丢失登录状态、配置或本地数据库；优先在应用设置中清理。' })
            }
            $completedDirectories++
            if ($ProgressPath) {
                $progress = [pscustomobject]@{ Completed=$completedDirectories; Total=$totalDirectories; Current=$directory.Name; Scope=$root.Scope }
                [System.IO.File]::WriteAllText($ProgressPath, ($progress | ConvertTo-Json -Compress), [System.Text.UTF8Encoding]::new($false))
            }
        }
    }
    return @($results | Sort-Object Bytes -Descending)
}

function Get-CleanerInventory {
    $items = @()
    $seen = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    $candidates = @(
        @{ Id='temp'; Name='用户临时文件'; Path=$env:TEMP; Purpose='应用安装、解压和运行时产生的短期文件。'; Level='建议清理'; Impact='正在使用的文件会自动跳过；少数应用可能需要重新创建临时文件。'; Default=$false },
        @{ Id='crashdumps'; Name='应用崩溃转储'; Path=(Join-Path $env:LOCALAPPDATA 'CrashDumps'); Purpose='应用崩溃时保存的诊断信息，主要供开发者排查问题。'; Level='建议清理'; Impact='删除后无法用这些旧转储分析历史崩溃。'; Default=$false },
        @{ Id='d3dscache'; Name='DirectX 着色器缓存'; Path=(Join-Path $env:LOCALAPPDATA 'D3DSCache'); Purpose='显卡驱动和游戏保存的已编译着色器，用于缩短画面加载时间。'; Level='建议清理'; Impact='不会删除游戏存档；游戏下次运行时会重新编译，初次加载可能卡顿。'; Default=$false },
        @{ Id='werarchive'; Name='Windows 错误报告存档'; Path=(Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportArchive'); Purpose='当前用户应用崩溃后生成的历史诊断报告。'; Level='建议清理'; Impact='删除后无法使用这些旧报告排查历史故障。'; Default=$false },
        @{ Id='werqueue'; Name='Windows 错误报告队列'; Path=(Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\WER\ReportQueue'); Purpose='等待提交或处理的当前用户错误诊断报告。'; Level='谨慎清理'; Impact='尚未提交的错误报告会丢失，但不影响应用本身。'; Default=$false },
        @{ Id='npmcache'; Name='npm 下载缓存'; Path=(Join-Path $env:LOCALAPPDATA 'npm-cache'); Purpose='Node.js 包管理器保存的已下载软件包副本。'; Level='谨慎清理'; Impact='不会删除项目；以后安装依赖时需要重新下载。'; Default=$false },
        @{ Id='pipcache'; Name='pip 下载缓存'; Path=(Join-Path $env:LOCALAPPDATA 'pip\Cache'); Purpose='Python 包管理器保存的安装包和网络响应缓存。'; Level='谨慎清理'; Impact='不会删除虚拟环境；以后安装 Python 包时需要重新下载。'; Default=$false },
        @{ Id='yarncache'; Name='Yarn 下载缓存'; Path=(Join-Path $env:LOCALAPPDATA 'Yarn\Cache'); Purpose='Yarn 包管理器保存的 JavaScript 软件包副本。'; Level='谨慎清理'; Impact='不会删除项目；以后安装依赖时需要重新下载。'; Default=$false },
        @{ Id='pnpmstore'; Name='pnpm 包存储'; Path=(Join-Path $env:LOCALAPPDATA 'pnpm\store'); Purpose='pnpm 跨项目复用的软件包内容寻址存储。'; Level='谨慎清理'; Impact='项目文件不会删除，但后续安装可能需要重新下载并重建链接。'; Default=$false },
        @{ Id='gradlecache'; Name='Gradle 构建缓存'; Path=(Join-Path $env:USERPROFILE '.gradle\caches'); Purpose='Gradle 下载的依赖、转换结果和构建缓存。'; Level='谨慎清理'; Impact='不会删除源码；下一次 Android/Java 构建会重新下载依赖，耗时较长。'; Default=$false },
        @{ Id='mavenrepo'; Name='Maven 本地仓库'; Path=(Join-Path $env:USERPROFILE '.m2\repository'); Purpose='Maven 下载的依赖，以及通过 mvn install 安装到本机的构件。'; Level='手动审查'; Impact='不会删除源码，但可能删除无法从远程仓库重新下载的本地构件；建议优先按 group/artifact 局部处理。'; Default=$false },
        @{ Id='cargocache'; Name='Cargo 包下载缓存'; Path=(Join-Path $env:USERPROFILE '.cargo\registry\cache'); Purpose='Rust Cargo 已下载的 crate 压缩包缓存。'; Level='谨慎清理'; Impact='不会删除 Rust 项目；后续构建可能需要重新下载依赖。'; Default=$false },
        @{ Id='gobuildcache'; Name='Go 构建缓存'; Path=(Join-Path $env:LOCALAPPDATA 'go-build'); Purpose='Go 编译器保存的中间构建结果。'; Level='谨慎清理'; Impact='不会删除源码；下一次构建会重新编译。'; Default=$false },
        @{ Id='inetcache'; Name='Windows 网络缓存'; Path=(Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\INetCache'); Purpose='部分 Windows 组件和旧式网页控件使用的网络缓存。'; Level='谨慎清理'; Impact='相关组件首次重新加载内容时可能稍慢。'; Default=$false },
        @{ Id='recentitems'; Name='最近使用项目记录'; Path=(Join-Path $env:APPDATA 'Microsoft\Windows\Recent'); Purpose='开始菜单和文件选择器中的最近使用文件快捷方式。'; Level='手动审查'; Impact='不会删除原文件，但会清空部分“最近使用”历史。'; Default=$false }
    )

    foreach ($candidate in $candidates) {
        if ([string]::IsNullOrWhiteSpace([string]$candidate.Path)) { continue }
        $item = New-CleanerItem -Id $candidate.Id -Name $candidate.Name -Path $candidate.Path `
            -Purpose $candidate.Purpose -Level $candidate.Level -Impact $candidate.Impact -DefaultSelected $candidate.Default
        if ($item -and $seen.Add($item.Path)) { $items += $item }
    }

    $explorerCache = New-CleanerItem -Id 'explorerthumbs' -Name 'Explorer 缩略图与图标缓存' `
        -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer') `
        -Purpose '资源管理器为图片、视频和文件图标保存的预览数据库。' -Level '谨慎清理' `
        -Impact '不会删除原文件；预览图会逐步重新生成。正在使用的数据库可能被跳过。' `
        -DeleteMode PatternFiles -Patterns @('thumbcache_*.db','iconcache_*.db')
    if ($explorerCache -and $explorerCache.Bytes -gt 0 -and $seen.Add($explorerCache.Path + '|patterns')) { $items += $explorerCache }

    foreach ($nugetPart in @('v3-cache','plugins-cache','scratch')) {
        $nugetPath = Join-Path $env:LOCALAPPDATA ('NuGet\' + $nugetPart)
        $nugetItem = New-CleanerItem -Id ('nuget_' + $nugetPart) -Name ('NuGet 缓存：' + $nugetPart) `
            -Path $nugetPath -Purpose 'NuGet 为 .NET 项目保存的下载包、插件或临时缓存。' -Level '谨慎清理' `
            -Impact '不会删除项目；还原依赖时可能需要重新下载。'
        if ($nugetItem -and $seen.Add($nugetItem.Path)) { $items += $nugetItem }
    }

    $items += Get-ProfileCacheFolders -BrowserRoot (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data') -BrowserName 'Edge'
    $items += Get-ProfileCacheFolders -BrowserRoot (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data') -BrowserName 'Chrome'

    $items += Get-DiscoveredAppDataCaches -ExistingPaths @($items | ForEach-Object Path)

    $downloads = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Downloads'
    if (Test-Path -LiteralPath $downloads) {
        $cutoff = (Get-Date).AddDays(-30)
        $oldFiles = @(Get-ChildItem -LiteralPath $downloads -File -Force -ErrorAction SilentlyContinue |
            Where-Object {
                -not (Test-IsReparsePoint $_) -and
                $_.LastWriteTime -lt $cutoff -and
                $_.Name -ne 'desktop.ini' -and
                $_.Name -notlike '~$*' -and
                ($_.Attributes -band ([System.IO.FileAttributes]::Hidden -bor [System.IO.FileAttributes]::System)) -eq 0
            } |
            Sort-Object Length -Descending | Select-Object -First 200)
        foreach ($file in $oldFiles) {
            $item = New-CleanerItem -Id ('download_' + $file.Name.GetHashCode()) -Name ('旧下载：' + $file.Name) `
                -Path $file.FullName -Purpose '这是下载目录中超过 30 天未修改的个人文件。' -Level '手动审查' `
                -Impact '它可能是重要文档或安装包。确认不再需要后再勾选；删除会送入回收站。' -DeleteMode File
            if ($item) { $items += $item }
        }
    }

    return @($items | Sort-Object @{Expression='Level'; Descending=$false}, @{Expression='Bytes'; Descending=$true})
}

function Test-ProtectedPath {
    param([Parameter(Mandatory)][string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    $protected = @($env:windir, $env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData) |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($root in $protected) {
        $safeRoot = [System.IO.Path]::GetFullPath($root).TrimEnd('\')
        if ($full.Equals($safeRoot, [System.StringComparison]::OrdinalIgnoreCase) -or
            $full.StartsWith($safeRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Remove-ToRecycleBin {
    param([Parameter(Mandatory)][System.IO.FileSystemInfo]$Item)
    if (Test-IsReparsePoint $Item) { throw "拒绝处理链接或重解析点：$($Item.FullName)" }
    if (Test-ProtectedPath $Item.FullName) { throw "拒绝处理系统保护路径：$($Item.FullName)" }

    if (-not ('WindowsCClear.NativeRecycleBin' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

namespace WindowsCClear {
    public static class NativeRecycleBin {
        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct SHFILEOPSTRUCT {
            public IntPtr hwnd;
            public uint wFunc;
            [MarshalAs(UnmanagedType.LPWStr)] public string pFrom;
            [MarshalAs(UnmanagedType.LPWStr)] public string pTo;
            public ushort fFlags;
            [MarshalAs(UnmanagedType.Bool)] public bool fAnyOperationsAborted;
            public IntPtr hNameMappings;
            [MarshalAs(UnmanagedType.LPWStr)] public string lpszProgressTitle;
        }

        [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
        private static extern int SHFileOperation(ref SHFILEOPSTRUCT operation);

        public static void Move(string path) {
            // FO_DELETE and FOF_SILENT | FOF_NOCONFIRMATION | FOF_ALLOWUNDO | FOF_NOERRORUI.
            var operation = new SHFILEOPSTRUCT {
                wFunc = 3,
                pFrom = path + "\0\0",
                pTo = null,
                fFlags = 0x0004 | 0x0010 | 0x0040 | 0x0400
            };
            int result = SHFileOperation(ref operation);
            if (result != 0) throw new Win32Exception(result);
            if (operation.fAnyOperationsAborted) {
                throw new OperationCanceledException("回收站操作被中止；可能有文件正在使用。");
            }
        }
    }
}
'@
    }

    [WindowsCClear.NativeRecycleBin]::Move($Item.FullName)
}

function Remove-CleanerItem {
    param([Parameter(Mandatory)]$CleanerItem)
    if ($CleanerItem.Kind -ne '用户级数据') { throw '系统级数据不允许删除。' }
    if (Test-ProtectedPath $CleanerItem.Path) { throw '该路径位于系统保护范围。' }

    $removed = 0
    $failed = 0
    $errors = @()
    if ($CleanerItem.DeleteMode -eq 'File') {
        $targets = @(Get-Item -LiteralPath $CleanerItem.Path -Force -ErrorAction SilentlyContinue)
    } elseif ($CleanerItem.DeleteMode -eq 'PatternFiles') {
        $patterns = @($CleanerItem.Patterns)
        $targets = @(Get-ChildItem -LiteralPath $CleanerItem.Path -File -Force -ErrorAction SilentlyContinue | Where-Object {
            $matched = $false
            foreach ($pattern in $patterns) { if ($_.Name -like $pattern) { $matched = $true; break } }
            $matched -and -not (Test-IsReparsePoint $_)
        })
    } else {
        $targets = @(Get-ChildItem -LiteralPath $CleanerItem.Path -Force -ErrorAction SilentlyContinue)
    }

    foreach ($target in $targets) {
        try {
            Remove-ToRecycleBin -Item $target
            $removed++
        } catch {
            $failed++
            $errors += $_.Exception.Message
        }
    }
    [pscustomobject]@{ Removed=$removed; Failed=$failed; Errors=$errors }
}

function Get-ProtectedLocations {
    @(
        [pscustomobject]@{ Name='Windows 系统目录'; Path=$env:windir; Purpose='操作系统核心文件、更新组件和系统服务。'; Policy='受保护：不可删除' },
        [pscustomobject]@{ Name='程序安装目录'; Path=$env:ProgramFiles; Purpose='已安装应用及其共享组件。'; Policy='受保护：请通过“设置 > 应用”卸载' },
        [pscustomobject]@{ Name='系统公共数据'; Path=$env:ProgramData; Purpose='系统服务和所有用户共享的应用数据。'; Policy='受保护：不可在本工具中删除' }
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_.Path) }
}

function Get-SystemManagedCleanupItems {
    @(
        [pscustomobject]@{ Name='回收站'; Location='C:\$Recycle.Bin'; Purpose='已经删除、仍可恢复的文件，可能继续占用大量磁盘空间。'; Reason='清空后无法通过回收站恢复，因此不与普通“移到回收站”操作混在一起。'; Action='确认内容后右键回收站 > 清空回收站' },
        [pscustomobject]@{ Name='Windows Update 清理'; Location="$env:windir\SoftwareDistribution"; Purpose='已下载的更新包和被新版本替代的更新组件。'; Reason='更新数据库与服务状态必须保持一致，不能直接删除目录。'; Action='设置 > 系统 > 存储 > 临时文件' },
        [pscustomobject]@{ Name='Windows 组件存储'; Location="$env:windir\WinSxS"; Purpose='系统组件、功能和更新回滚所需文件。'; Reason='文件大量使用硬链接，资源管理器显示大小也可能重复计算。'; Action='使用 Windows“临时文件”或 DISM 组件清理' },
        [pscustomobject]@{ Name='传递优化缓存'; Location="$env:windir\SoftwareDistribution\DeliveryOptimization"; Purpose='Windows 更新在设备间传输时使用的缓存。'; Reason='应由传递优化服务协调清理。'; Action='设置 > 系统 > 存储 > 临时文件' },
        [pscustomobject]@{ Name='以前的 Windows 安装'; Location='C:\Windows.old'; Purpose='系统大版本升级前的旧 Windows，用于短期回退。'; Reason='删除后无法回退到旧版本，且需要系统权限。'; Action='设置 > 系统 > 存储 > 临时文件' },
        [pscustomobject]@{ Name='系统错误转储'; Location="$env:windir\MEMORY.DMP"; Purpose='蓝屏后用于定位驱动或内核故障的完整/内核转储。'; Reason='可能仍有诊断价值，且位于系统保护目录。'; Action='确认无需排障后使用 Windows 临时文件清理' },
        [pscustomobject]@{ Name='系统临时文件'; Location="$env:windir\Temp"; Purpose='系统服务和安装程序产生的临时数据。'; Reason='部分文件正在使用，需要系统工具安全跳过。'; Action='设置 > 系统 > 存储 > 临时文件' },
        [pscustomobject]@{ Name='设备驱动程序包'; Location="$env:windir\System32\DriverStore"; Purpose='当前和备用硬件驱动程序。'; Reason='直接删除可能导致设备无法工作或无法回滚驱动。'; Action='使用磁盘清理或设备管理器' },
        [pscustomobject]@{ Name='休眠文件'; Location='C:\hiberfil.sys'; Purpose='保存休眠状态，也可能被“快速启动”功能使用。'; Reason='不能直接删除；关闭休眠会同时失去休眠功能，并可能影响快速启动。'; Action='确认不需要休眠后，以管理员身份运行 powercfg /hibernate off' },
        [pscustomobject]@{ Name='分页文件'; Location='C:\pagefile.sys'; Purpose='内存不足和崩溃转储时使用的虚拟内存。'; Reason='直接删除或盲目禁用可能导致应用崩溃、内存不足和转储失败。'; Action='系统属性 > 高级 > 性能 > 虚拟内存，通常保持自动管理' },
        [pscustomobject]@{ Name='OneDrive 本地副本'; Location=(Join-Path $env:USERPROFILE 'OneDrive'); Purpose='已同步到云端、同时保留在本机的文件副本。'; Reason='应使用“释放空间”保留云端文件，不能把普通删除当作清缓存。'; Action='确认已同步后右键文件或目录 > 释放空间' },
        [pscustomobject]@{ Name='系统还原点'; Location='System Volume Information'; Purpose='系统保护、卷影副本和文件历史恢复数据。'; Reason='直接访问受保护，删除会失去恢复能力。'; Action='系统保护 > 配置，按需管理占用' }
    )
}
