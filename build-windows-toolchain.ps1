Param (
  $msysPath = "C:\tools\msys64",
  $mingwPlatform = "mingw64"
)

$mingw_script = @'
# Ensure we're being run from one of MSYS2's "native shells".
case "$MSYSTEM" in
    "MINGW64")
        PKG_PREFIX="mingw-w64-x86_64"
        MINGW_INSTALLS="mingw64"
        BUNDLE_ARCH="w64"
        ;;
    "MINGW32")
        PKG_PREFIX="mingw-w64-i686"
        MINGW_INSTALLS="mingw32"
        BUNDLE_ARCH="w32"
        ;;
    *)
        echo >&2 "$0 must only be called from a MINGW64/32 login shell."
        read -p "bad"
        exit 1
        ;;
esac

pacman -S --noconfirm --needed --noprogressbar \
  zip \
  ${PKG_PREFIX}-python3 \
  ${PKG_PREFIX}-gcc \
  ${PKG_PREFIX}-nsis \
  ${PKG_PREFIX}-binutils \
  ${PKG_PREFIX}-python-pip \
  ${PKG_PREFIX}-python-setuptools \
  git

pip3 install --break-system-packages --upgrade git+https://github.com/achadwick/styrene

# Patch styrene for Python 3.13+ compatibility (SafeConfigParser was removed)
STYRENE_CMDLINE=$(python3 -c "import styrene.cmdline; print(styrene.cmdline.__file__)")
sed -i 's/configparser\.SafeConfigParser/configparser.ConfigParser/g' "$STYRENE_CMDLINE"

rm -rf ~/toolchain
styrene --no-exe --no-zip --color=no -o ./output ./windows-toolchain.cfg
'@

Remove-Item "./arm-toolchain" -Recurse -ErrorAction Ignore
Remove-Item "./output" -Recurse -ErrorAction Ignore
Remove-Item "./artifact" -Recurse -ErrorAction Ignore

New-Item -ItemType Directory -Force -Path ./output
New-Item -ItemType Directory -Force -Path ./arm-toolchain
New-Item -ItemType Directory -Force -Path ./artifact

Write-Information -MessageData "Obtaining unix tools for $mingwPlatform" -InformationAction Continue

# Write script to a temp file without BOM to avoid bash parsing issues
$tempScriptPath = Join-Path $env:TEMP "mingw_script.sh"
[System.IO.File]::WriteAllText($tempScriptPath, $mingw_script, [System.Text.UTF8Encoding]::new($false))
Get-Content $tempScriptPath | & $msysPath\msys2_shell.cmd -here -$mingwPlatform -no-start -defterm

Write-Information -MessageData "Downloading Arm Embedded Toolchain" -InformationAction Continue
$client = New-Object System.Net.Webclient
$ARM_ZIP_URL = "https://developer.arm.com/-/media/Files/downloads/gnu/15.2.rel1/binrel/arm-gnu-toolchain-15.2.rel1-mingw-w64-x86_64-arm-none-eabi.zip"
$zipfile = "./gcc-arm-none-eabi.zip"
$client.DownloadFile($ARM_ZIP_URL, $zipfile)

$arm_toolchain_dir = "./arm-toolchain"

Write-Information -MessageData "Extracting Arm Embedded Toolchain" -InformationAction Continue
Expand-Archive -Path $zipfile -DestinationPath $arm_toolchain_dir

# Debug: Show what was extracted
Write-Host "Contents of arm-toolchain after extraction:"
Get-ChildItem -Path $arm_toolchain_dir -Recurse -Depth 3 | ForEach-Object { 
  Write-Host "  $($_.FullName)"
}

# Get only the first (and should be only) top-level directory from styrene output
$toolchain_dir = (Get-ChildItem -Path "./output" -Directory | Select-Object -First 1).Name

# Find the ARM toolchain root - it could be:
# 1. A subdirectory containing bin/arm-none-eabi-gcc.exe
# 2. The arm-toolchain dir itself if files extracted directly
$arm_toolchain_root = $null

# First check if gcc is directly in arm-toolchain/bin
if (Test-Path "$arm_toolchain_dir/bin/arm-none-eabi-gcc.exe") {
  $arm_toolchain_root = (Resolve-Path $arm_toolchain_dir).Path
  Write-Host "Found ARM toolchain directly in: $arm_toolchain_root"
}
else {
  # Look in subdirectories
  $found = Get-ChildItem -Path $arm_toolchain_dir -Directory | Where-Object {
    Test-Path (Join-Path $_.FullName "bin/arm-none-eabi-gcc.exe")
  } | Select-Object -First 1
    
  if ($found) {
    $arm_toolchain_root = $found.FullName
    Write-Host "Found ARM toolchain in subdirectory: $arm_toolchain_root"
  }
}

# Debug output
Write-Host "Toolchain dir: $toolchain_dir"
Write-Host "ARM toolchain root: $arm_toolchain_root"

if (-not $toolchain_dir) {
  Write-Error "Failed to find styrene output directory in ./output"
  exit 1
}

if (-not $arm_toolchain_root) {
  Write-Error "Failed to find ARM toolchain directory containing bin/arm-none-eabi-gcc.exe"
  Write-Host "Searching for arm-none-eabi-gcc.exe anywhere in arm-toolchain:"
  Get-ChildItem -Path $arm_toolchain_dir -Recurse -Filter "arm-none-eabi-gcc.exe" | ForEach-Object {
    Write-Host "  Found: $($_.FullName)"
  }
  exit 1
}

Write-Information -MessageData "Removing extra files from Arm Embedded Toolchain" -InformationAction Continue
Remove-Item "$arm_toolchain_root\share" -Recurse -ErrorAction Ignore

Write-Information -MessageData "Combining Toolchains with Unix Tools" -InformationAction Continue

# List what we're about to copy
Write-Host "Contents of ARM toolchain root:"
Get-ChildItem -Path $arm_toolchain_root | ForEach-Object { Write-Host "  - $($_.Name)" }

Write-Host "Contents of output usr folder before merge:"
Get-ChildItem -Path "./output/$toolchain_dir/usr" | ForEach-Object { Write-Host "  - $($_.Name)" }

Get-ChildItem -Path $arm_toolchain_root | ForEach-Object {
  $itemName = $_.Name
  $sourcePath = $_.FullName
  $destPath = Join-Path "./output/$toolchain_dir/usr" $itemName
  
  Write-Host "Processing: $itemName"
  
  if (Test-Path -Path $destPath) {
    Write-Host "  Merging into existing folder: $destPath"
    Copy-Item -Path "$sourcePath\*" -Destination $destPath -Recurse -Force
  }
  else {
    Write-Host "  Copying new folder to: ./output/$toolchain_dir/usr"
    Copy-Item -Path $sourcePath -Destination "./output/$toolchain_dir/usr" -Recurse -Force
  }
}

Write-Host "Contents of output usr folder after merge:"
Get-ChildItem -Path "./output/$toolchain_dir/usr" | ForEach-Object { Write-Host "  - $($_.Name)" }

# Verify arm-none-eabi-gcc exists
$gccPath = "./output/$toolchain_dir/usr/bin/arm-none-eabi-gcc.exe"
if (Test-Path $gccPath) {
    Write-Host "SUCCESS: ARM GCC found at $gccPath"
} else {
    Write-Error "FAILED: ARM GCC not found at $gccPath"
    Write-Host "Contents of bin folder:"
    Get-ChildItem -Path "./output/$toolchain_dir/usr/bin" -Filter "arm-*" | ForEach-Object { Write-Host "  $($_.Name)" }
    exit 1
}

Write-Information -MessageData "Creating Compressed Archive" -InformationAction Continue
Compress-Archive -Path "./output/$toolchain_dir/usr" -DestinationPath "./artifact/pros-toolchain-windows.zip"