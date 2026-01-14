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

# Get only the first (and should be only) top-level directory
$toolchain_dir = (Get-ChildItem -Path "./output" -Directory | Select-Object -First 1).Name
$arm_toolchain_subdir = (Get-ChildItem -Path $arm_toolchain_dir -Directory | Select-Object -First 1).Name

# Debug output
Write-Information -MessageData "Toolchain dir: $toolchain_dir" -InformationAction Continue
Write-Information -MessageData "ARM toolchain subdir: $arm_toolchain_subdir" -InformationAction Continue

if (-not $toolchain_dir) {
  Write-Error "Failed to find styrene output directory in ./output"
  exit 1
}

if (-not $arm_toolchain_subdir) {
  Write-Error "Failed to find ARM toolchain directory in $arm_toolchain_dir"
  exit 1
}

Write-Information -MessageData "Removing extra files from Arm Embedded Toolchain" -InformationAction Continue
Remove-Item "$arm_toolchain_dir\$arm_toolchain_subdir\share" -Recurse -ErrorAction Ignore

Write-Information -MessageData "Combining Toolchains with Unix Tools" -InformationAction Continue

# List what we're about to copy
Write-Information -MessageData "Contents of ARM toolchain:" -InformationAction Continue
Get-ChildItem -Path "$arm_toolchain_dir\$arm_toolchain_subdir" | ForEach-Object { Write-Information -MessageData "  - $($_.Name)" -InformationAction Continue }

Write-Information -MessageData "Contents of output usr folder before merge:" -InformationAction Continue
Get-ChildItem -Path "./output/$toolchain_dir/usr" | ForEach-Object { Write-Information -MessageData "  - $($_.Name)" -InformationAction Continue }

Get-ChildItem -Path "$arm_toolchain_dir\$arm_toolchain_subdir" | ForEach-Object {
  $itemName = $_.Name
  $sourcePath = Join-Path "$arm_toolchain_dir\$arm_toolchain_subdir" $itemName
  $destPath = Join-Path "./output/$toolchain_dir/usr" $itemName
  
  Write-Information -MessageData "Processing: $itemName" -InformationAction Continue
  
  if (Test-Path -Path $destPath) {
    Write-Information -MessageData "  Merging into existing folder: $destPath" -InformationAction Continue
    Copy-Item -Path "$sourcePath\*" -Destination $destPath -Recurse -Force
  }
  else {
    Write-Information -MessageData "  Copying new folder to: ./output/$toolchain_dir/usr" -InformationAction Continue
    Copy-Item -Path $sourcePath -Destination "./output/$toolchain_dir/usr" -Recurse -Force
  }
}

Write-Information -MessageData "Contents of output usr folder after merge:" -InformationAction Continue
Get-ChildItem -Path "./output/$toolchain_dir/usr" | ForEach-Object { Write-Information -MessageData "  - $($_.Name)" -InformationAction Continue }

# Verify arm-none-eabi-gcc exists
$gccPath = "./output/$toolchain_dir/usr/bin/arm-none-eabi-gcc.exe"
if (Test-Path $gccPath) {
    Write-Information -MessageData "SUCCESS: ARM GCC found at $gccPath" -InformationAction Continue
} else {
    Write-Error "FAILED: ARM GCC not found at $gccPath"
    exit 1
}

Write-Information -MessageData "Creating Compressed Archive" -InformationAction Continue
Compress-Archive -Path "./output/$toolchain_dir/usr" -DestinationPath "./artifact/pros-toolchain-windows.zip"