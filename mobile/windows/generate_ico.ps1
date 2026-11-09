param(
    [string]$InputPath = "mobile\assets\images\app_icon.png",
    [string]$OutputPath = "mobile\windows\runner\resources\app_icon.ico"
)

Add-Type -AssemblyName System.Drawing

$source = [System.Drawing.Bitmap]::FromFile((Resolve-Path $InputPath))
$Sizes = @(16, 24, 32, 48, 64, 128, 256)
$pngStreams = [System.Collections.Generic.List[byte[]]]::new()
$actualSizes = [System.Collections.Generic.List[int]]::new()

foreach ($size in $Sizes) {
    $resized = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($resized)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.Clear([System.Drawing.Color]::Transparent)
    $g.DrawImage($source, 0, 0, $size, $size)
    $g.Dispose()

    $ms = New-Object System.IO.MemoryStream
    $resized.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $ms.ToArray()
    $ms.Dispose()
    $resized.Dispose()

    $pngStreams.Add($bytes)
    $actualSizes.Add($size)
}
$source.Dispose()

$targetFullPath = [System.IO.Path]::GetFullPath($OutputPath)
$targetDir = [System.IO.Path]::GetDirectoryName($targetFullPath)
if (-not (Test-Path $targetDir)) {
    New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
}

$fs = [System.IO.File]::Create($targetFullPath)
$bw = New-Object System.IO.BinaryWriter $fs

# ICONDIR header
$bw.Write([uint16]0) # Reserved
$bw.Write([uint16]1) # Resource Type (1 = Icon)
$bw.Write([uint16]$actualSizes.Count) # Image Count

# Calculate offset of image data: Header (6 bytes) + Entries (16 * Count bytes)
$offset = 6 + (16 * $actualSizes.Count)

# ICONDIRENTRY entries
for ($i = 0; $i -lt $actualSizes.Count; $i++) {
    $w = $actualSizes[$i]
    $h = $actualSizes[$i]
    $byteW = [byte]0
    if ($w -lt 256) { $byteW = [byte]$w }
    $byteH = [byte]0
    if ($h -lt 256) { $byteH = [byte]$h }

    $bw.Write($byteW)
    $bw.Write($byteH)
    $bw.Write([byte]0) # Color count
    $bw.Write([byte]0) # Reserved
    $bw.Write([uint16]1) # Color planes
    $bw.Write([uint16]32) # Bits per pixel
    $bw.Write([uint32]$pngStreams[$i].Length) # Size of image data
    $bw.Write([uint32]$offset) # Offset
    $offset += $pngStreams[$i].Length
}

# Write image data
for ($i = 0; $i -lt $actualSizes.Count; $i++) {
    $bw.Write($pngStreams[$i])
}

$bw.Flush()
$bw.Close()
$fs.Close()

Write-Output "Successfully generated: $targetFullPath (Size: $((Get-Item $targetFullPath).Length) bytes)"
