@echo off
chcp 65001 >nul
setlocal
 title LOCATION APP - PTSC V4
 echo.
 echo ============================================================
 echo                 LOCATION APP - PTSC V4
 echo ============================================================
 echo Dang khoi dong bo may chu tich hop cua Windows...
 echo Khong can Python, khong can cai them phan mem.
 echo.
 powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Location_App_Server.ps1"
 if errorlevel 1 (
   echo.
   echo Co loi khi khoi dong. Hay chup anh man hinh gui lai.
   pause
 )
endlocal
