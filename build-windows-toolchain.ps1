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

pip3 install --upgrade git+git://github.com/achadwick/styrene.git

rm -rf ~/toolchain
styrene --no-exe --color=no -o ~/toolchain ./windows-toolchain.cfg
cp ~/toolchain/*.zip ./output
'@

Remove-Item "./arm-toolchain" -Recurse -ErrorAction Ignore
Remove-Item "./output" -Recurse -ErrorAction Ignore

New-Item -ItemType Directory -Force -Path ./output
New-Item -ItemType Directory -Force -Path ./arm-toolchain

Write-Information "Obtaining unix tools for $mingwPlatform"
Write-Output $mingw_script | & $msysPath\msys2_shell.cmd -here -$mingwPlatform -no-start -defterm

Write-Information "Downloading Arm Embedded Toolchain"
$client = New-Object System.Net.Webclient
$ARM_ZIP_URL = "https://developer.arm.com/-/media/Files/downloads/gnu-rm/10.3-2021.07/gcc-arm-none-eabi-10.3-2021.07-win32.zip"
$zipfile = "./gcc-arm-none-eabi.zip"
$client.DownloadFile($ARM_ZIP_URL, $zipfile)

$arm_toolchain_dir = "./arm-toolchain"

Write-Information "Extracting Arm Embedded Toolchain"
7z x -o"$arm_toolchain_dir/usr" $zipfile

Write-Information "Removing extra files from Arm Embedded Toolchain"
Remove-Item "$arm_toolchain_dir/usr/share" -Recurse -ErrorAction Ignore

Write-Information "Adding Combining Toolchains with Unix Tools"
Get-ChildItem "./output" -Filter *.zip | ForEach-Object {
    7z d "./output/$_" ./_scripts ./mingw*
    7z a "./output/$_" ./arm-toolchain/*
}

exit 0
