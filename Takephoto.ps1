# Đảm bảo luồng chạy là STA để hỗ trợ giao diện Form và Tray Icon mượt mòi
[System.Threading.Thread]::CurrentThread.SetApartmentState([System.Threading.ApartmentState]::STA)

# 1. Cấu hình thư mục lưu ảnh ngoài Desktop
$TargetDir = "$Home\Desktop\ChupManHinh_Space"
if (!(Test-Path $TargetDir)) { New-Item -ItemType Directory -Path $TargetDir | Out-Null }

# Thông tin cấu hình Khởi động cùng Windows (Registry)
$RegistryPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run"
$RegistryName = "SpaceBarScreenshotTool"
# Lệnh thực thi chạy ngầm không hiện cửa sổ bậy bạ
$StartupCommand = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""

# Load các thư viện đồ họa hệ thống
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# API bắt phím hệ thống
$Signatures = @'
[DllImport("user32.dll")]
public static extern short GetAsyncKeyState(int vKey);
'@
$User32 = Add-Type -MemberDefinition $Signatures -Name "User32" -Namespace "Win32" -PassThru

# --- KHỞI TẠO TRAY ICON ---
$NotifyIcon = New-Object System.Windows.Forms.NotifyIcon
$NotifyIcon.Icon = [System.Drawing.SystemIcons]::Shield 
$NotifyIcon.Text = "Tool Chụp Màn Hình Spacebar (Đang chạy...)"
$NotifyIcon.Visible = $true

# Biến kiểm soát trạng thái chạy và tạm dừng
$script:Running = $true
$script:Paused = $false
$script:LastShot = [DateTime]::Now

# Tạo menu chuột phải
$ContextMenu = New-Object System.Windows.Forms.ContextMenu

# 1. Nút Tạm dừng / Tiếp tục
$PauseMenuItem = New-Object System.Windows.Forms.MenuItem
$PauseMenuItem.Text = "Pause (Tạm dừng)"
$ContextMenu.MenuItems.Add($PauseMenuItem) | Out-Null

# 2. Nút Khởi động cùng Windows (Có Checkbox)
$StartupMenuItem = New-Object System.Windows.Forms.MenuItem
$StartupMenuItem.Text = "Khởi động cùng Windows"
# Kiểm tra xem hiện tại đã cài khởi động cùng Win chưa để đánh dấu tích
if (Get-ItemProperty -Path $RegistryPath -Name $RegistryName -ErrorAction SilentlyContinue) {
    $StartupMenuItem.Checked = $true
}
$ContextMenu.MenuItems.Add($StartupMenuItem) | Out-Null

# 3. Nút Thoát hoàn toàn
$ExitMenuItem = New-Object System.Windows.Forms.MenuItem
$ExitMenuItem.Text = "Exit Tool (Thoát)"
$ContextMenu.MenuItems.Add($ExitMenuItem) | Out-Null

$NotifyIcon.ContextMenu = $ContextMenu

# --- XỬ LÝ SỰ KIỆN MENU ---

# Xử lý nút Tạm dừng
$PauseMenuItem.add_Click({
    if ($script:Paused) {
        $script:Paused = $false
        $PauseMenuItem.Text = "Pause (Tạm dừng)"
        $NotifyIcon.Text = "Tool Chụp Màn Hình Spacebar (Đang chạy...)"
        $NotifyIcon.ShowBalloonTip(2000, "Tool Chụp Màn Hình", "Đã TIẾP TỤC chạy ngầm!", [System.Windows.Forms.ToolTipIcon]::Info)
    } else {
        $script:Paused = $true
        $PauseMenuItem.Text = "Resume (Tiếp tục)"
        $NotifyIcon.Text = "Tool Chụp Màn Hình Spacebar (Đang TẠM DỪNG)"
        $NotifyIcon.ShowBalloonTip(2000, "Tool Chụp Màn Hình", "Đã TẠM DỪNG chụp ảnh!", [System.Windows.Forms.ToolTipIcon]::Warning)
    }
})

# Xử lý nút Khởi động cùng Windows
$StartupMenuItem.add_Click({
    if ($PSCommandPath) {
        if ($StartupMenuItem.Checked) {
            # Nếu đang bật -> Tắt đi và xóa Registry
            Remove-ItemProperty -Path $RegistryPath -Name $RegistryName -ErrorAction SilentlyContinue
            $StartupMenuItem.Checked = $false
            $NotifyIcon.ShowBalloonTip(2000, "Khởi động", "Đã HỦY khởi động cùng Windows!", [System.Windows.Forms.ToolTipIcon]::Info)
        } else {
            # Nếu đang tắt -> Bật lên và ghi Registry
            Set-ItemProperty -Path $RegistryPath -Name $RegistryName -Value $StartupCommand
            $StartupMenuItem.Checked = $true
            $NotifyIcon.ShowBalloonTip(2000, "Khởi động", "Đã BẬT khởi động cùng Windows thành công!", [System.Windows.Forms.ToolTipIcon]::Info)
        }
    } else {
        [System.Windows.Forms.MessageBox]::Show("Bạn cần lưu file script này thành định dạng .ps1 trước thì mới cài Khởi động cùng Win được nhé!", "Thông báo")
    }
})

# Xử lý nút Thoát
$ExitMenuItem.add_Click({
    $script:Running = $false
    $NotifyIcon.Visible = $false
    $NotifyIcon.Dispose()
    $MainForm.Close()
    [System.Windows.Forms.Application]::Exit()
})

# Tạo form ngầm quản lý giao diện
$MainForm = New-Object System.Windows.Forms.Form
$MainForm.ShowInTaskbar = $false
$MainForm.WindowState = 'Minimized'

# Hiện thông báo khởi động thành công
$NotifyIcon.ShowBalloonTip(3000, "Tool Chụp Màn Hình", "Tool đã chạy ngầm! Ấn SPACE để chụp. Chuột phải để cài đặt.", [System.Windows.Forms.ToolTipIcon]::Info)

# --- ẨN CỬA SỔ LỆNH WINDOWS ---
$ShowWindowSignatures = @'
[DllImport("user32.dll")]
public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
'@
$Win32ShowWindow = Add-Type -MemberDefinition $ShowWindowSignatures -Name "Win32ShowWindow" -Namespace "Win32" -PassThru
$Process = Get-Process -Id $PID
$Win32ShowWindow::ShowWindow($Process.MainWindowHandle, 0)

# --- VÒNG LẶP QUÉT PHÍM CHẠY NGẦM ---
$FormAction = {
    while ($script:Running) {
        [System.Windows.Forms.Application]::DoEvents()

        if (-not $script:Paused) {
            if ($User32::GetAsyncKeyState(0x20) -and 0x8000) {
                $TimeDiff = [DateTime]::Now.Subtract($script:LastShot).TotalMilliseconds
                if ($TimeDiff -gt 400) {
                    $script:LastShot = [DateTime]::Now
                    
                    # SỬA LỖI: Tự động kiểm tra / tạo lại nếu folder bị đổi tên hoặc xóa
                    if (!(Test-Path $TargetDir)) { 
                        New-Item -ItemType Directory -Path $TargetDir | Out-Null 
                    }
                    
                    $Bitmap = $null
                    $Graphic = $null
                    try {
                        $Screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
                        $Bitmap = New-Object System.Drawing.Bitmap $Screen.Width, $Screen.Height
                        $Graphic = [System.Drawing.Graphics]::FromImage($Bitmap)
                        
                        $Graphic.CopyFromScreen($Screen.X, $Screen.Y, 0, 0, $Bitmap.Size)
                        
                        $TimeStamp = (Get-Date).ToString("yyyyMMdd_HHmmss_fff")
                        $FileName = "Space_TrayShot_${TimeStamp}.png"
                        $FilePath = Join-Path $TargetDir $FileName
                        
                        $Bitmap.Save($FilePath, [System.Drawing.Imaging.ImageFormat]::Png)
                    }
                    catch {
                        $NotifyIcon.ShowBalloonTip(1000, "Lỗi", "Không thể lưu ảnh!", [System.Windows.Forms.ToolTipIcon]::Error)
                    }
                    finally {
                        if ($Graphic -ne $null) { $Graphic.Dispose() }
                        if ($Bitmap -ne $null) { $Bitmap.Dispose() }
                    }
                }
            }
        }
        Start-Sleep -Milliseconds 40
    }
}
$MainForm.add_Shown($FormAction)
[System.Windows.Forms.Application]::Run($MainForm)
