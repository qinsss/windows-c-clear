param(
    [switch]$HeadlessScan,
    [switch]$HeadlessQuickScan,
    [switch]$HeadlessAppDataExact,
    [string]$OutputPath,
    [string]$ProgressPath,
    [switch]$SmokeTest
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Cleaner.Core.ps1')

if ($HeadlessScan) {
    Get-CleanerInventory | ConvertTo-Json -Depth 4
    exit 0
}

if ($HeadlessQuickScan) {
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { throw '快速扫描需要 OutputPath。' }
    if ($ProgressPath) { [System.IO.File]::WriteAllText($ProgressPath, '正在识别可清理候选…', [System.Text.UTF8Encoding]::new($false)) }
    $quickItems = @(Get-CleanerInventory)
    if ($ProgressPath) { [System.IO.File]::WriteAllText($ProgressPath, '正在估算 AppData 应用数据…', [System.Text.UTF8Encoding]::new($false)) }
    $quickAppData = @(Get-AppDataUsageInventory)
    $payload = [pscustomobject]@{ Items=$quickItems; AppData=$quickAppData }
    [System.IO.File]::WriteAllText($OutputPath, ($payload | ConvertTo-Json -Depth 5), [System.Text.UTF8Encoding]::new($false))
    exit 0
}

if ($HeadlessAppDataExact) {
    if ([string]::IsNullOrWhiteSpace($OutputPath)) { throw '精确扫描需要 OutputPath。' }
    $json = @(Get-AppDataUsageInventory -Exact -ProgressPath $ProgressPath) | ConvertTo-Json -Depth 4
    [System.IO.File]::WriteAllText($OutputPath, $json, [System.Text.UTF8Encoding]::new($false))
    exit 0
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace WindowsCClear {
    public static class TaskbarIdentity {
        [DllImport("shell32.dll", SetLastError = true)]
        private static extern int SetCurrentProcessExplicitAppUserModelID(
            [MarshalAs(UnmanagedType.LPWStr)] string appID);

        [DllImport("user32.dll", CharSet = CharSet.Unicode)]
        private static extern IntPtr SendMessage(IntPtr window, uint message, IntPtr wParam, IntPtr lParam);

        public static void SetAppId(string appId) {
            int result = SetCurrentProcessExplicitAppUserModelID(appId);
            if (result < 0) Marshal.ThrowExceptionForHR(result);
        }

        public static void SetWindowIcon(IntPtr window, IntPtr icon) {
            const uint WM_SETICON = 0x0080;
            SendMessage(window, WM_SETICON, IntPtr.Zero, icon);
            SendMessage(window, WM_SETICON, new IntPtr(1), icon);
        }
    }
}
'@
[WindowsCClear.TaskbarIdentity]::SetAppId('WindowsCClear.CDriveCleaner.v2')

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="C 盘清理助手" Height="760" Width="1120" MinHeight="620" MinWidth="900"
        WindowStartupLocation="CenterScreen" Background="#F4F7FB" FontFamily="Microsoft YaHei UI">
  <Window.Resources>
    <Style x:Key="BaseButton" TargetType="Button">
      <Setter Property="Padding" Value="16,9"/>
      <Setter Property="Margin" Value="0,0,10,0"/>
      <Setter Property="BorderThickness" Value="1"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="ButtonBorder" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="7" Padding="{TemplateBinding Padding}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.86"/></Trigger>
              <Trigger Property="IsPressed" Value="True"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.70"/></Trigger>
              <Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="ButtonBorder" Property="BorderBrush" Value="#173B65"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="ButtonBorder" Property="Opacity" Value="0.42"/><Setter Property="Cursor" Value="Arrow"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="Button" BasedOn="{StaticResource BaseButton}">
      <Setter Property="Background" Value="#E7EDF6"/><Setter Property="Foreground" Value="#183153"/><Setter Property="BorderBrush" Value="#D4DEEB"/>
    </Style>
    <Style x:Key="InfoButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
      <Setter Property="Background" Value="#E8F1FD"/><Setter Property="Foreground" Value="#245C9E"/><Setter Property="BorderBrush" Value="#C9DDF5"/>
    </Style>
    <Style x:Key="SettingsButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
      <Setter Property="Background" Value="#EEEAFE"/><Setter Property="Foreground" Value="#5944A9"/><Setter Property="BorderBrush" Value="#D8D0FA"/>
    </Style>
    <Style x:Key="ExactButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
      <Setter Property="Background" Value="#FFF2D6"/><Setter Property="Foreground" Value="#8A5B08"/><Setter Property="BorderBrush" Value="#F1D79B"/>
    </Style>
    <Style x:Key="PrimaryButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
      <Setter Property="Background" Value="#2F6FED"/><Setter Property="Foreground" Value="White"/><Setter Property="BorderBrush" Value="#2F6FED"/>
    </Style>
    <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource BaseButton}">
      <Setter Property="Background" Value="#DC4C57"/><Setter Property="Foreground" Value="White"/><Setter Property="BorderBrush" Value="#DC4C57"/>
    </Style>
    <Style TargetType="TabItem">
      <Setter Property="Foreground" Value="#536A84"/>
      <Setter Property="Background" Value="#EAF0F7"/>
      <Setter Property="FontWeight" Value="SemiBold"/>
      <Setter Property="Padding" Value="17,9"/>
      <Setter Property="Margin" Value="0,0,6,0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="TabItem">
            <Border x:Name="TabBorder" Background="{TemplateBinding Background}" CornerRadius="7,7,0,0"
                    BorderBrush="#D7E1EC" BorderThickness="1,1,1,0" Padding="{TemplateBinding Padding}">
              <ContentPresenter ContentSource="Header" HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True"><Setter TargetName="TabBorder" Property="Background" Value="#DCE8F8"/><Setter Property="Foreground" Value="#245C9E"/></Trigger>
              <Trigger Property="IsSelected" Value="True"><Setter TargetName="TabBorder" Property="Background" Value="#2F6FED"/><Setter TargetName="TabBorder" Property="BorderBrush" Value="#2F6FED"/><Setter Property="Foreground" Value="White"/></Trigger>
              <Trigger Property="IsEnabled" Value="False"><Setter TargetName="TabBorder" Property="Opacity" Value="0.45"/></Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
    <Style TargetType="DataGridColumnHeader">
      <Setter Property="Background" Value="#EAF0F8"/><Setter Property="Foreground" Value="#38506E"/>
      <Setter Property="Padding" Value="10"/><Setter Property="BorderThickness" Value="0,0,1,1"/>
    </Style>
  </Window.Resources>
  <Grid>
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/><RowDefinition Height="*"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <Border Grid.Row="0" Background="#173B65" Padding="28,22">
      <Grid>
        <StackPanel>
          <TextBlock Text="C 盘清理助手" FontSize="28" FontWeight="SemiBold" Foreground="White"/>
          <TextBlock Text="先弄清数据的作用，再决定是否删除" FontSize="14" Foreground="#C8D8EA" Margin="0,7,0,0"/>
        </StackPanel>
        <Border HorizontalAlignment="Right" Background="#264D77" CornerRadius="8" Padding="16,10">
          <StackPanel><TextBlock Text="安全模式" Foreground="#8DFFCB" FontWeight="SemiBold"/>
          <TextBlock Text="仅用户数据 · 删除到回收站" Foreground="White" FontSize="12" Margin="0,3,0,0"/></StackPanel>
        </Border>
      </Grid>
    </Border>

    <Border Grid.Row="1" Margin="24,18,24,12" Background="White" CornerRadius="10" Padding="18">
      <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock x:Name="SummaryText" Text="准备扫描当前用户可清理的数据" FontSize="17" FontWeight="SemiBold" Foreground="#183153"/>
          <TextBlock x:Name="StatusText" Text="系统目录会显示说明，但永远不会进入删除列表。" Foreground="#60738B" Margin="0,5,0,0"/>
          <ProgressBar x:Name="ScanProgress" Height="5" Margin="0,10,0,0" Minimum="0" Maximum="100"
                       Foreground="#2F6FED" Background="#E7EDF6" Visibility="Collapsed"/>
        </StackPanel>
        <StackPanel Grid.Column="1" Orientation="Horizontal" VerticalAlignment="Center">
          <Button x:Name="SystemInfoButton" Content="查看系统级数据" Style="{StaticResource InfoButton}"/>
          <Button x:Name="WindowsCleanupButton" Content="Windows 清理设置" Style="{StaticResource SettingsButton}"/>
          <Button x:Name="ExactScanButton" Content="精确扫描 AppData" Style="{StaticResource ExactButton}"/>
          <Button x:Name="ScanButton" Content="开始扫描" Style="{StaticResource PrimaryButton}"/>
        </StackPanel>
      </Grid>
    </Border>

    <Border Grid.Row="2" Margin="24,0,24,14" Background="White" CornerRadius="10" Padding="1">
      <TabControl BorderThickness="0" Background="White">
       <TabItem Header="可清理候选">
        <DataGrid x:Name="ItemsGrid" AutoGenerateColumns="False" CanUserAddRows="False" CanUserDeleteRows="False"
                IsReadOnly="False" HeadersVisibility="Column" GridLinesVisibility="Horizontal" BorderThickness="0"
                RowHeaderWidth="0" AlternatingRowBackground="#F8FAFD" SelectionMode="Single">
        <DataGrid.Columns>
          <DataGridTemplateColumn Header="选择" Width="60" IsReadOnly="False">
            <DataGridTemplateColumn.CellTemplate>
              <DataTemplate>
                <CheckBox IsChecked="{Binding Selected, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"
                          HorizontalAlignment="Center" VerticalAlignment="Center" Cursor="Hand"/>
              </DataTemplate>
            </DataGridTemplateColumn.CellTemplate>
          </DataGridTemplateColumn>
          <DataGridTextColumn Header="数据" Binding="{Binding Name}" Width="220" IsReadOnly="True"/>
          <DataGridTextColumn Header="大小" Binding="{Binding Size}" Width="90" IsReadOnly="True"/>
          <DataGridTextColumn Header="建议" Binding="{Binding Level}" Width="90" IsReadOnly="True"/>
          <DataGridTextColumn Header="作用" Binding="{Binding Purpose}" Width="*" MinWidth="220" IsReadOnly="True"/>
          <DataGridTextColumn Header="删除后的影响" Binding="{Binding Impact}" Width="1.25*" MinWidth="260" IsReadOnly="True"/>
        </DataGrid.Columns>
        </DataGrid>
       </TabItem>
       <TabItem Header="AppData（应用数据）">
        <DataGrid x:Name="AppDataGrid" AutoGenerateColumns="False" CanUserAddRows="False" CanUserDeleteRows="False"
                  IsReadOnly="False" HeadersVisibility="Column" GridLinesVisibility="Horizontal" BorderThickness="0"
                  RowHeaderWidth="0" AlternatingRowBackground="#F8FAFD" SelectionMode="Single">
          <DataGrid.Columns>
            <DataGridTemplateColumn Header="选择" Width="60" IsReadOnly="False">
              <DataGridTemplateColumn.CellTemplate>
                <DataTemplate>
                  <CheckBox IsChecked="{Binding Selected, Mode=TwoWay, UpdateSourceTrigger=PropertyChanged}"
                            HorizontalAlignment="Center" VerticalAlignment="Center" Cursor="Hand"/>
                </DataTemplate>
              </DataGridTemplateColumn.CellTemplate>
            </DataGridTemplateColumn>
            <DataGridTextColumn Header="应用/厂商" Binding="{Binding Name}" Width="170" IsReadOnly="True"/>
            <DataGridTextColumn Header="区域" Binding="{Binding Scope}" Width="75" IsReadOnly="True"/>
            <DataGridTextColumn Header="大小" Binding="{Binding Size}" Width="90" IsReadOnly="True"/>
            <DataGridTextColumn Header="文件数" Binding="{Binding FileCount}" Width="75" IsReadOnly="True"/>
            <DataGridTextColumn Header="作用" Binding="{Binding Purpose}" Width="*" MinWidth="240" IsReadOnly="True"/>
            <DataGridTextColumn Header="风险提示" Binding="{Binding Advice}" Width="1.15*" MinWidth="280" IsReadOnly="True"/>
          </DataGrid.Columns>
        </DataGrid>
       </TabItem>
       <TabItem Header="Windows 系统清理项">
        <DataGrid x:Name="SystemCleanupGrid" AutoGenerateColumns="False" CanUserAddRows="False" CanUserDeleteRows="False"
                  IsReadOnly="True" HeadersVisibility="Column" GridLinesVisibility="Horizontal" BorderThickness="0"
                  RowHeaderWidth="0" AlternatingRowBackground="#F8FAFD" SelectionMode="Single">
          <DataGrid.Columns>
            <DataGridTextColumn Header="项目" Binding="{Binding Name}" Width="170"/>
            <DataGridTextColumn Header="作用" Binding="{Binding Purpose}" Width="*" MinWidth="240"/>
            <DataGridTextColumn Header="为何不直接删除" Binding="{Binding Reason}" Width="1.1*" MinWidth="260"/>
            <DataGridTextColumn Header="安全处理方式" Binding="{Binding Action}" Width="240"/>
          </DataGrid.Columns>
        </DataGrid>
       </TabItem>
      </TabControl>
    </Border>

    <Border Grid.Row="3" Background="White" BorderBrush="#DDE5EF" BorderThickness="0,1,0,0" Padding="24,16">
      <Grid><Grid.ColumnDefinitions><ColumnDefinition/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
        <StackPanel>
          <TextBlock x:Name="SelectedText" Text="尚未选择任何项目" FontWeight="SemiBold" Foreground="#183153"/>
          <Border Background="#E8F3FF" BorderBrush="#BBD8F5" BorderThickness="1" CornerRadius="6" Padding="10,6" Margin="0,7,18,0">
            <TextBlock Text="提示：双击某一项可在资源管理器中查看实际位置，也可自行在资源管理器中进行删除。"
                       Foreground="#1E5C96" FontSize="14" FontWeight="SemiBold"/>
          </Border>
        </StackPanel>
        <Button Grid.Column="1" x:Name="CleanButton" Content="移到回收站" Style="{StaticResource DangerButton}" IsEnabled="False" Margin="0"/>
      </Grid>
    </Border>
  </Grid>
</Window>
'@

$reader = [System.Xml.XmlNodeReader]::new($xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)
$iconPath = Join-Path $PSScriptRoot 'app.ico'
$script:nativeTaskbarIcon = $null
if (Test-Path -LiteralPath $iconPath) {
    $window.Icon = [System.Windows.Media.Imaging.BitmapFrame]::Create([System.Uri]::new($iconPath))
    $script:nativeTaskbarIcon = [System.Drawing.Icon]::new($iconPath)
    $window.Add_SourceInitialized({
        $helper = [System.Windows.Interop.WindowInteropHelper]::new($window)
        [WindowsCClear.TaskbarIdentity]::SetWindowIcon($helper.Handle, $script:nativeTaskbarIcon.Handle)
    })
}
$grid = $window.FindName('ItemsGrid')
$appDataGrid = $window.FindName('AppDataGrid')
$systemCleanupGrid = $window.FindName('SystemCleanupGrid')
$scanButton = $window.FindName('ScanButton')
$exactScanButton = $window.FindName('ExactScanButton')
$cleanButton = $window.FindName('CleanButton')
$systemInfoButton = $window.FindName('SystemInfoButton')
$windowsCleanupButton = $window.FindName('WindowsCleanupButton')
$summaryText = $window.FindName('SummaryText')
$statusText = $window.FindName('StatusText')
$scanProgress = $window.FindName('ScanProgress')
$selectedText = $window.FindName('SelectedText')
$script:items = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
$script:appDataItems = [System.Collections.ObjectModel.ObservableCollection[object]]::new()
$script:quickScanProcess = $null
$script:quickScanOutput = $null
$script:quickScanProgress = $null
$script:quickTimer = $null
$script:exactScanProcess = $null
$script:exactScanOutput = $null
$script:exactScanProgress = $null
$script:exactTimer = $null
$grid.ItemsSource = $script:items
$appDataGrid.ItemsSource = $script:appDataItems
$systemCleanupGrid.ItemsSource = @(Get-SystemManagedCleanupItems)

if ($SmokeTest) {
    Write-Output 'WPF interface loaded successfully.'
    exit 0
}

function Update-SelectionSummary {
    $grid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true) | Out-Null
    $appDataGrid.CommitEdit([System.Windows.Controls.DataGridEditingUnit]::Cell, $true) | Out-Null
    $selected = @($script:items | Where-Object Selected) + @($script:appDataItems | Where-Object Selected)
    [long]$bytes = Measure-CleanerItemsBytes -Items $selected
    if ($selected.Count -eq 0) {
        $selectedText.Text = '尚未选择任何项目'
        $cleanButton.IsEnabled = $false
    } else {
        $appDataCount = @($selected | Where-Object { $_.Source -eq 'AppData' }).Count
        $riskText = if ($appDataCount -gt 0) { "；其中 $appDataCount 项为高风险 AppData" } else { '' }
        $selectedText.Text = "已选择 $($selected.Count) 项，共 $(Format-ByteSize $bytes)$riskText"
        $cleanButton.IsEnabled = $true
    }
}

function Queue-SelectionSummaryUpdate {
    $window.Dispatcher.BeginInvoke([action]{ Update-SelectionSummary }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
}

function Get-OverlappingSelection {
    param([object[]]$Items)
    for ($i = 0; $i -lt $Items.Count; $i++) {
        $left = [System.IO.Path]::GetFullPath([string]$Items[$i].Path).TrimEnd('\')
        for ($j = $i + 1; $j -lt $Items.Count; $j++) {
            $right = [System.IO.Path]::GetFullPath([string]$Items[$j].Path).TrimEnd('\')
            if ($left.Equals($right, [System.StringComparison]::OrdinalIgnoreCase) -or
                $left.StartsWith($right + '\', [System.StringComparison]::OrdinalIgnoreCase) -or
                $right.StartsWith($left + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
                return [pscustomobject]@{ Left=$Items[$i]; Right=$Items[$j] }
            }
        }
    }
    return $null
}

function Start-Scan {
    if ($script:quickScanProcess -and -not $script:quickScanProcess.HasExited) { return }
    $script:quickScanOutput = Join-Path ([System.IO.Path]::GetTempPath()) ("WindowsCClear-Quick-{0}.json" -f [guid]::NewGuid())
    $script:quickScanProgress = Join-Path ([System.IO.Path]::GetTempPath()) ("WindowsCClear-QuickProgress-{0}.txt" -f [guid]::NewGuid())
    $engineName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $enginePath = Join-Path $PSHOME $engineName
    if (-not (Test-Path -LiteralPath $enginePath)) { $enginePath = $engineName }
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -HeadlessQuickScan -OutputPath `"$($script:quickScanOutput)`" -ProgressPath `"$($script:quickScanProgress)`""

    try {
        $script:quickScanProcess = Start-Process -FilePath $enginePath -ArgumentList $arguments -WindowStyle Hidden -PassThru
    } catch {
        [System.Windows.MessageBox]::Show("无法启动扫描：`n$($_.Exception.Message)", '启动失败', 'OK', 'Error') | Out-Null
        return
    }

    $scanButton.IsEnabled = $false
    $exactScanButton.IsEnabled = $false
    $cleanButton.IsEnabled = $false
    $scanProgress.Visibility = 'Visible'
    $scanProgress.IsIndeterminate = $true
    $statusText.Text = '正在启动后台扫描…'
    $scanButton.Content = '扫描中…'

    $script:quickTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:quickTimer.Interval = [TimeSpan]::FromMilliseconds(500)
    $script:quickTimer.Add_Tick({
        if (-not $script:quickScanProcess) { return }
        if (-not $script:quickScanProcess.HasExited) {
            if ($script:quickScanProgress -and (Test-Path -LiteralPath $script:quickScanProgress)) {
                try { $statusText.Text = [System.IO.File]::ReadAllText($script:quickScanProgress, [System.Text.Encoding]::UTF8) } catch {}
            }
            return
        }

        $script:quickTimer.Stop()
        $exitCode = $script:quickScanProcess.ExitCode
        try {
            if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $script:quickScanOutput)) { throw "扫描进程退出代码：$exitCode" }
            $raw = [System.IO.File]::ReadAllText($script:quickScanOutput, [System.Text.Encoding]::UTF8)
            $payload = ConvertFrom-Json -InputObject $raw
            $script:items.Clear()
            foreach ($item in $payload.Items) { $script:items.Add($item) }
            $script:appDataItems.Clear()
            foreach ($item in $payload.AppData) { $script:appDataItems.Add($item) }
            [long]$appTotal = Measure-CleanerItemsBytes -Items @($script:appDataItems)
            $estimatedCount = @($script:appDataItems | Where-Object { $_.Size -like '≥*' }).Count
            $appLabel = if ($estimatedCount -gt 0) { "AppData 快速估算至少 $(Format-ByteSize $appTotal)" } else { "AppData 共 $(Format-ByteSize $appTotal)" }
            $summaryText.Text = "发现 $($script:items.Count) 个可清理候选；$appLabel"
            $statusText.Text = '扫描完成。只有明确勾选的用户级数据才会处理，占用中的文件会跳过。'
            Update-SelectionSummary
        } catch {
            [System.Windows.MessageBox]::Show("扫描失败：`n$($_.Exception.Message)", '扫描失败', 'OK', 'Error') | Out-Null
            $statusText.Text = '扫描未完成。'
        } finally {
            foreach ($temporaryPath in @($script:quickScanOutput, $script:quickScanProgress)) {
                if ($temporaryPath -and (Test-Path -LiteralPath $temporaryPath)) { Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue }
            }
            $script:quickScanProcess = $null
            $script:quickScanOutput = $null
            $script:quickScanProgress = $null
            $scanProgress.IsIndeterminate = $false
            $scanProgress.Visibility = 'Collapsed'
            $scanButton.IsEnabled = $true
            $exactScanButton.IsEnabled = $true
            $scanButton.Content = '重新扫描'
        }
    })
    $script:quickTimer.Start()
}

function Start-ExactAppDataScan {
    if ($script:exactScanProcess -and -not $script:exactScanProcess.HasExited) { return }
    $answer = [System.Windows.MessageBox]::Show(
        "精确扫描会完整遍历当前用户的 AppData，可能需要几分钟。`n`n扫描只读取文件大小，不会删除或修改数据。是否继续？",
        '精确扫描 AppData', 'YesNo', 'Information')
    if ($answer -ne 'Yes') { return }

    $script:exactScanOutput = Join-Path ([System.IO.Path]::GetTempPath()) ("WindowsCClear-AppData-{0}.json" -f [guid]::NewGuid())
    $script:exactScanProgress = Join-Path ([System.IO.Path]::GetTempPath()) ("WindowsCClear-Progress-{0}.json" -f [guid]::NewGuid())
    $engineName = if ($PSVersionTable.PSEdition -eq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
    $enginePath = Join-Path $PSHOME $engineName
    if (-not (Test-Path -LiteralPath $enginePath)) { $enginePath = $engineName }
    $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -HeadlessAppDataExact -OutputPath `"$($script:exactScanOutput)`" -ProgressPath `"$($script:exactScanProgress)`""

    try {
        $script:exactScanProcess = Start-Process -FilePath $enginePath -ArgumentList $arguments -WindowStyle Hidden -PassThru
    } catch {
        [System.Windows.MessageBox]::Show("无法启动精确扫描：`n$($_.Exception.Message)", '启动失败', 'OK', 'Error') | Out-Null
        return
    }

    $exactScanButton.IsEnabled = $false
    $scanButton.IsEnabled = $false
    $cleanButton.IsEnabled = $false
    $exactScanButton.Content = '精确扫描进行中…'
    $statusText.Text = '正在后台完整遍历 AppData；你可以继续查看当前列表。'
    $scanProgress.IsIndeterminate = $false
    $scanProgress.Value = 0
    $scanProgress.Visibility = 'Visible'

    $script:exactTimer = [System.Windows.Threading.DispatcherTimer]::new()
    $script:exactTimer.Interval = [TimeSpan]::FromMilliseconds(750)
    $script:exactTimer.Add_Tick({
        if (-not $script:exactScanProcess) { return }
        if (-not $script:exactScanProcess.HasExited) {
            if ($script:exactScanProgress -and (Test-Path -LiteralPath $script:exactScanProgress)) {
                try {
                    $progressJson = [System.IO.File]::ReadAllText($script:exactScanProgress, [System.Text.Encoding]::UTF8)
                    $progressInfo = $progressJson | ConvertFrom-Json
                    if ([int]$progressInfo.Total -gt 0) {
                        $percent = [math]::Min(100, [math]::Round(([double]$progressInfo.Completed / [double]$progressInfo.Total) * 100))
                        $scanProgress.Value = $percent
                        $statusText.Text = "精确扫描 AppData：$($progressInfo.Completed)/$($progressInfo.Total)（$percent%） · $($progressInfo.Scope)\$($progressInfo.Current)"
                    }
                } catch {
                    # The worker may be replacing the tiny progress file while it is read; retry next tick.
                }
            }
            return
        }
        $script:exactTimer.Stop()
        $exitCode = $script:exactScanProcess.ExitCode
        try {
            if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $script:exactScanOutput)) {
                throw "扫描进程退出代码：$exitCode"
            }
            $raw = [System.IO.File]::ReadAllText($script:exactScanOutput, [System.Text.Encoding]::UTF8)
            # Explicit enumeration handles the JSON-array behavior difference between
            # Windows PowerShell 5.1 and PowerShell 7.
            $exactItems = @(ConvertFrom-AppDataInventoryJson -Json $raw)
            $script:appDataItems.Clear()
            foreach ($item in $exactItems) { $script:appDataItems.Add($item) }
            [long]$exactTotal = Measure-CleanerItemsBytes -Items @($script:appDataItems)
            $summaryText.Text = "发现 $($script:items.Count) 个可清理候选；AppData 精确大小 $(Format-ByteSize $exactTotal)"
            $statusText.Text = "AppData 精确扫描完成，共统计 $($script:appDataItems.Count) 个应用或厂商目录。"
        } catch {
            [System.Windows.MessageBox]::Show("精确扫描失败：`n$($_.Exception.Message)", '扫描失败', 'OK', 'Error') | Out-Null
            $statusText.Text = '精确扫描未完成，仍保留快速估算结果。'
        } finally {
            if ($script:exactScanOutput -and (Test-Path -LiteralPath $script:exactScanOutput)) {
                Remove-Item -LiteralPath $script:exactScanOutput -Force -ErrorAction SilentlyContinue
            }
            if ($script:exactScanProgress -and (Test-Path -LiteralPath $script:exactScanProgress)) {
                Remove-Item -LiteralPath $script:exactScanProgress -Force -ErrorAction SilentlyContinue
            }
            $script:exactScanProcess = $null
            $script:exactScanOutput = $null
            $script:exactScanProgress = $null
            $scanProgress.Value = 100
            $scanProgress.Visibility = 'Collapsed'
            $exactScanButton.Content = '精确扫描 AppData'
            $exactScanButton.IsEnabled = $true
            $scanButton.IsEnabled = $true
            Update-SelectionSummary
        }
    })
    $script:exactTimer.Start()
}

$scanButton.Add_Click({ Start-Scan })
$exactScanButton.Add_Click({ Start-ExactAppDataScan })
$grid.Add_CurrentCellChanged({ Queue-SelectionSummaryUpdate })
$grid.Add_CellEditEnding({ Queue-SelectionSummaryUpdate })
$grid.Add_PreviewMouseLeftButtonUp({ Queue-SelectionSummaryUpdate })
$appDataGrid.Add_CurrentCellChanged({ Queue-SelectionSummaryUpdate })
$appDataGrid.Add_CellEditEnding({ Queue-SelectionSummaryUpdate })
$appDataGrid.Add_PreviewMouseLeftButtonUp({ Queue-SelectionSummaryUpdate })
$grid.Add_MouseDoubleClick({
    if ($grid.SelectedItem -and (Test-Path -LiteralPath $grid.SelectedItem.Path)) {
        $target = if ($grid.SelectedItem.DeleteMode -eq 'File') { "/select,`"$($grid.SelectedItem.Path)`"" } else { $grid.SelectedItem.Path }
        Start-Process explorer.exe -ArgumentList $target
    }
})
$appDataGrid.Add_MouseDoubleClick({
    if ($appDataGrid.SelectedItem -and (Test-Path -LiteralPath $appDataGrid.SelectedItem.Path)) {
        Start-Process explorer.exe -ArgumentList $appDataGrid.SelectedItem.Path
    }
})

$systemInfoButton.Add_Click({
    $lines = Get-ProtectedLocations | ForEach-Object { "• $($_.Name)`n  $($_.Path)`n  $($_.Purpose)`n  $($_.Policy)" }
    [System.Windows.MessageBox]::Show(($lines -join "`n`n"), '系统级数据（仅说明）', 'OK', 'Information') | Out-Null
})

$windowsCleanupButton.Add_Click({
    try {
        Start-Process 'ms-settings:storagesense'
    } catch {
        Start-Process cleanmgr.exe
    }
})

$cleanButton.Add_Click({
    Update-SelectionSummary
    $selected = @($script:items | Where-Object Selected) + @($script:appDataItems | Where-Object Selected)
    if ($selected.Count -eq 0) { return }
    $overlap = Get-OverlappingSelection -Items $selected
    if ($overlap) {
        [System.Windows.MessageBox]::Show(
            "以下选择范围互相包含，请取消其中一项后再试：`n`n• $($overlap.Left.Name)`n  $($overlap.Left.Path)`n`n• $($overlap.Right.Name)`n  $($overlap.Right.Path)",
            '存在重复删除范围', 'OK', 'Warning') | Out-Null
        return
    }
    [long]$bytes = Measure-CleanerItemsBytes -Items $selected
    $selectionLines = @($selected | Select-Object -First 8 | ForEach-Object {
        $scope = if ($_.DeleteMode -eq 'File') { '删除该文件' } elseif ($_.DeleteMode -eq 'PatternFiles') { '处理匹配的缓存文件' } else { '清空该目录的全部内容' }
        "• $($_.Name) — $scope`n  $($_.Path)"
    })
    if ($selected.Count -gt 8) { $selectionLines += "• 其余 $($selected.Count - 8) 项…" }
    $answer = [System.Windows.MessageBox]::Show(
        "将处理 $($selected.Count) 个已勾选项目（约 $(Format-ByteSize $bytes)）：`n`n$($selectionLines -join "`n")`n`n占用中的文件会静默跳过；系统级目录不会被处理。是否继续？",
        '确认清理', 'YesNo', 'Warning')
    if ($answer -ne 'Yes') { return }

    $appDataSelected = @($selected | Where-Object { $_.Source -eq 'AppData' })
    if ($appDataSelected.Count -gt 0) {
        $appDataPaths = @($appDataSelected | Select-Object -First 6 | ForEach-Object { "• $($_.Scope)\$($_.Name)`n  $($_.Path)" })
        if ($appDataSelected.Count -gt 6) { $appDataPaths += "• 其余 $($appDataSelected.Count - 6) 项…" }
        $secondAnswer = [System.Windows.MessageBox]::Show(
            "第二次确认：将清空 $($appDataSelected.Count) 个 AppData 目录的全部内容。`n`n$($appDataPaths -join "`n")`n`n这可能导致应用退出登录、设置重置、本地数据库或未同步数据丢失。请先关闭相关应用。确定继续吗？",
            '高风险 AppData 删除确认', 'YesNo', 'Error')
        if ($secondAnswer -ne 'Yes') { return }
    }

    $cleanButton.IsEnabled = $false
    $scanButton.IsEnabled = $false
    $exactScanButton.IsEnabled = $false
    $window.Cursor = [System.Windows.Input.Cursors]::Wait
    $removed = 0; $failed = 0; $errorMessages = @()
    for ($selectedIndex = 0; $selectedIndex -lt $selected.Count; $selectedIndex++) {
        $item = $selected[$selectedIndex]
        $statusText.Text = "仅处理已选项目 $($selectedIndex + 1)/$($selected.Count)：$($item.Name)"
        [System.Windows.Threading.Dispatcher]::CurrentDispatcher.Invoke([action]{}, 'Background')
        $result = Remove-CleanerItem -CleanerItem $item
        $removed += $result.Removed
        $failed += $result.Failed
        $errorMessages += $result.Errors
    }
    $window.Cursor = [System.Windows.Input.Cursors]::Arrow
    $scanButton.IsEnabled = $true
    $exactScanButton.IsEnabled = $true
    $message = "已移动 $removed 个文件或文件夹到回收站。"
    if ($failed -gt 0) { $message += "`n$failed 项未能处理（通常是文件正在使用）。" }
    [System.Windows.MessageBox]::Show($message, '清理完成', 'OK', $(if ($failed) {'Warning'} else {'Information'})) | Out-Null
    Start-Scan
})

$window.Add_Closing({
    if ($script:quickTimer) { $script:quickTimer.Stop() }
    if ($script:quickScanProcess -and -not $script:quickScanProcess.HasExited) {
        $script:quickScanProcess.Kill()
    }
    foreach ($temporaryPath in @($script:quickScanOutput, $script:quickScanProgress)) {
        if ($temporaryPath -and (Test-Path -LiteralPath $temporaryPath)) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
    if ($script:exactTimer) { $script:exactTimer.Stop() }
    if ($script:exactScanProcess -and -not $script:exactScanProcess.HasExited) {
        $script:exactScanProcess.Kill()
    }
    if ($script:exactScanOutput -and (Test-Path -LiteralPath $script:exactScanOutput)) {
        Remove-Item -LiteralPath $script:exactScanOutput -Force -ErrorAction SilentlyContinue
    }
    if ($script:exactScanProgress -and (Test-Path -LiteralPath $script:exactScanProgress)) {
        Remove-Item -LiteralPath $script:exactScanProgress -Force -ErrorAction SilentlyContinue
    }
    if ($script:nativeTaskbarIcon) {
        $script:nativeTaskbarIcon.Dispose()
        $script:nativeTaskbarIcon = $null
    }
})
$window.ShowDialog() | Out-Null
