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
  ${PKG_PREFIX}-python3-pip \
  git

pip3 install --upgrade git+https://github.com/achadwick/styrene

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
Write-Output $mingw_script | & $msysPath\msys2_shell.cmd -here -$mingwPlatform -no-start -defterm

Write-Information -MessageData "Downloading Arm Embedded Toolchain" -InformationAction Continue
$client = New-Object System.Net.Webclient
$ARM_ZIP_URL = "https://developer.arm.com/-/media/Files/downloads/gnu/13.3.rel1/binrel/arm-gnu-toolchain-13.3.rel1-mingw-w64-i686-arm-none-eabi.zip"
$zipfile = "./gcc-arm-none-eabi.zip"
$client.DownloadFile($ARM_ZIP_URL, $zipfile)

$arm_toolchain_dir = "./arm-toolchain"

Write-Information -MessageData "Extracting Arm Embedded Toolchain" -InformationAction Continue
Expand-Archive -Path $zipfile -DestinationPath $arm_toolchain_dir

$arm_toolchain_dir = "./arm-toolchain"
$toolchain_dir = Get-ChildItem -Path "./output" -Directory -Name
$arm_toolchain_subdir = Get-ChildItem -Path $arm_toolchain_dir -Directory -Name

Write-Information -MessageData "Removing extra files from Arm Embedded Toolchain" -InformationAction Continue
Remove-Item "$arm_toolchain_dir/$arm_toolchain_subdir/share" -Recurse -ErrorAction Ignore

Write-Information -MessageData "Adding Combining Toolchains with Unix Tools" -InformationAction Continue
Get-ChildItem -Path $arm_toolchain_dir/$arm_toolchain_subdir | ForEach-Object {
    if (Test-Path -Path "./output/$toolchain_dir/usr/$_") {
        Copy-Item -Path $arm_toolchain_dir/$arm_toolchain_subdir/$_/* -Destination "./output/$toolchain_dir/usr/$_"
    } else {
        Copy-Item -Path $arm_toolchain_dir/$arm_toolchain_subdir/$_ -Destination "./output/$toolchain_dir/usr"
    }
}

Write-Information -MessageData "Creating Compressed Archive" -InformationAction Continue
Compress-Archive -Path "./output/$toolchain_dir/usr" -DestinationPath "./artifact/pros-toolchain-windows.zip"