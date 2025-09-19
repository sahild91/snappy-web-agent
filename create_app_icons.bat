@echo off
echo Creating Android app icons for Snappy Web Agent...
echo.

cd android-service\app\src\main\res

REM Create mipmap directories if they don't exist
if not exist mipmap-hdpi mkdir mipmap-hdpi
if not exist mipmap-mdpi mkdir mipmap-mdpi
if not exist mipmap-xhdpi mkdir mipmap-xhdpi
if not exist mipmap-xxhdpi mkdir mipmap-xxhdpi
if not exist mipmap-xxxhdpi mkdir mipmap-xxxhdpi
if not exist mipmap-anydpi-v26 mkdir mipmap-anydpi-v26

echo Creating placeholder icons using PowerShell...

REM Create simple colored squares as placeholder icons using PowerShell
powershell -Command "& {
    Add-Type -AssemblyName System.Drawing
    
    # Create different sized icons
    $sizes = @{
        'mipmap-mdpi' = 48
        'mipmap-hdpi' = 72
        'mipmap-xhdpi' = 96
        'mipmap-xxhdpi' = 144
        'mipmap-xxxhdpi' = 192
    }
    
    foreach ($folder in $sizes.Keys) {
        $size = $sizes[$folder]
        
        # Create bitmap
        $bitmap = New-Object System.Drawing.Bitmap($size, $size)
        $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
        
        # Fill with blue background
        $blueBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(33, 150, 243))
        $graphics.FillRectangle($blueBrush, 0, 0, $size, $size)
        
        # Add white 'S' text
        $font = New-Object System.Drawing.Font('Arial', ($size * 0.6), [System.Drawing.FontStyle]::Bold)
        $whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $format = New-Object System.Drawing.StringFormat
        $format.Alignment = [System.Drawing.StringAlignment]::Center
        $format.LineAlignment = [System.Drawing.StringAlignment]::Center
        
        $rect = New-Object System.Drawing.RectangleF(0, 0, $size, $size)
        $graphics.DrawString('S', $font, $whiteBrush, $rect, $format)
        
        # Save as PNG
        $bitmap.Save(\"$folder\ic_launcher.png\", [System.Drawing.Imaging.ImageFormat]::Png)
        
        # Cleanup
        $graphics.Dispose()
        $bitmap.Dispose()
        $blueBrush.Dispose()
        $whiteBrush.Dispose()
        $font.Dispose()
        
        Write-Host \"Created: $folder\ic_launcher.png ($size x $size)\"
    }
}"

if %errorlevel% neq 0 (
    echo PowerShell icon creation failed. Creating minimal placeholder files...
    
    REM Create minimal placeholder PNG files
    echo Creating minimal PNG placeholders...
    
    REM Use echo to create minimal binary files (this creates invalid PNGs but prevents build errors)
    echo. > mipmap-mdpi\ic_launcher.png
    echo. > mipmap-hdpi\ic_launcher.png  
    echo. > mipmap-xhdpi\ic_launcher.png
    echo. > mipmap-xxhdpi\ic_launcher.png
    echo. > mipmap-xxxhdpi\ic_launcher.png
    
    echo Warning: Created placeholder files only. Please replace with proper icons.
) else (
    echo ✓ App icons created successfully!
)

REM Create adaptive icon resources for API 26+
echo Creating adaptive icon resources...

REM Create ic_launcher_background.xml
(
echo ^<?xml version="1.0" encoding="utf-8"?^>
echo ^<vector xmlns:android="http://schemas.android.com/apk/res/android"
echo     android:width="108dp"
echo     android:height="108dp"
echo     android:viewportWidth="108"
echo     android:viewportHeight="108"^>
echo     ^<path
echo         android:fillColor="#2196F3"
echo         android:pathData="M0,0h108v108h-108z" /^>
echo ^</vector^>
) > drawable\ic_launcher_background.xml

REM Create ic_launcher_foreground.xml
(
echo ^<?xml version="1.0" encoding="utf-8"?^>
echo ^<vector xmlns:android="http://schemas.android.com/apk/res/android"
echo     android:width="108dp"
echo     android:height="108dp"
echo     android:viewportWidth="108"
echo     android:viewportHeight="108"^>
echo     ^<group
echo         android:scaleX="0.8"
echo         android:scaleY="0.8"
echo         android:translateX="10.8"
echo         android:translateY="10.8"^>
echo         ^<path
echo             android:fillColor="#FFFFFF"
echo             android:pathData="M20,20h68v68h-68z"
echo             android:strokeWidth="4"
echo             android:strokeColor="#FFFFFF" /^>
echo         ^<path
echo             android:fillColor="#FFFFFF"
echo             android:pathData="M35,35h38v8h-30v10h25v8h-25v10h30v8h-38z" /^>
echo     ^</group^>
echo ^</vector^>
) > drawable\ic_launcher_foreground.xml

REM Create adaptive icon
(
echo ^<?xml version="1.0" encoding="utf-8"?^>
echo ^<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android"^>
echo     ^<background android:drawable="@drawable/ic_launcher_background" /^>
echo     ^<foreground android:drawable="@drawable/ic_launcher_foreground" /^>
echo ^</adaptive-icon^>
) > mipmap-anydpi-v26\ic_launcher.xml

echo.
echo ✓ All icon resources created!
echo.
echo Icon summary:
echo - Created launcher icons for all densities
echo - Created adaptive icons for Android 8.0+
echo - Used blue background with white 'S' logo
echo.
echo Note: These are placeholder icons. For production, create proper icons using:
echo - Android Studio's Image Asset Studio
echo - Professional design tools
echo - Icon generators like https://romannurik.github.io/AndroidAssetStudio/
echo.

cd ..\..\..\..\..
pause