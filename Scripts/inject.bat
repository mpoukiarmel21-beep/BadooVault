@echo off
REM ============================================================
REM BadooVault - Inject Dylib into Badoo IPA (Windows)
REM LOCAL / manual fallback. The canonical build is CI
REM (.github/workflows/build.yml). This mirrors it on Windows.
REM ============================================================
REM Usage: inject.bat "path\to\Badoo.ipa"
REM ============================================================

setlocal enabledelayedexpansion

set INPUT=%~1
set DYLIB=obj\BadooVault.dylib
set WORKDIR=%TEMP%\BadooVault_%RANDOM%

if "%INPUT%"=="" (
    echo Usage: inject.bat "path\to\Badoo.ipa"
    echo.
    echo Example: inject.bat "D:\IPA APP\1467-Badoo_5.467.0_ThreadSaver.ipa"
    exit /b 1
)

if not exist "%INPUT%" (
    echo ERROR: %INPUT% not found
    exit /b 1
)

if not exist "%DYLIB%" (
    echo ERROR: %DYLIB% not found
    echo Build the tweak first or download from GitHub Actions
    exit /b 1
)

echo === BadooVault IPA Injector ===
echo.

echo [1/5] Extracting IPA...
mkdir "%WORKDIR%" 2>nul
cd /d "%WORKDIR%"
powershell -Command "Expand-Archive -Path '%INPUT%' -DestinationPath '.' -Force"

for /d %%d in (Payload\*.app) do set APP=%%d
echo   App: %APP%

echo [1b/5] Stripping bundled mod dylibs (clean base)...
for %%m in (Sideloadbypass1 Sideloadbypass2 ThreadSaver blatantsPatch) do (
    if exist "%APP%\Frameworks\%%m.dylib" (
        del /q "%APP%\Frameworks\%%m.dylib"
        echo   removed %%m.dylib
    )
)

echo [2/5] Copying dylib...
mkdir "%APP%\Frameworks" 2>nul
copy /Y "%OLDPWD%\%DYLIB%" "%APP%\Frameworks\BadooVault.dylib"

echo [3/5] Injecting load command...
REM Requires optool in PATH or same folder
where optool >nul 2>&1
if %errorlevel%==0 (
    optool install -c load -p @executable_path/Frameworks/BadooVault.dylib -t "%APP%\Badoo"
) else (
    echo   optool not found. Install it:
    echo   brew install optool  OR  download from GitHub
    echo.
    echo   Manual injection:
    echo   optool install -c load -p @executable_path/Frameworks\BadooVault.dylib -t "%APP%\Badoo"
    pause
    exit /b 1
)

echo [4/5] Signing...
where ldid >nul 2>&1
if %errorlevel%==0 (
    ldid -S "%APP%\Badoo"
    echo   Ad-hoc signed
) else (
    echo   ldid not found, skipping signature
)

echo [5/5] Creating IPA...
cd /d "%WORKDIR%"
powershell -Command "Compress-Archive -Path 'Payload' -DestinationPath '%OLDPWD%\BadooVault.ipa' -Force"

cd /d "%OLDPWD%"
rmdir /s /q "%WORKDIR%" 2>nul

echo.
echo === Done! ===
echo Output: BadooVault.ipa
echo Install via Sideloadly
