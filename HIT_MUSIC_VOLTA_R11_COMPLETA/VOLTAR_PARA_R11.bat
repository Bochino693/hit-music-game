@echo off
setlocal
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0VOLTAR_PARA_R11.ps1" -ProjectRoot "C:\Users\LAZER GAMES\Documents\beta-12"
set "CODE=%ERRORLEVEL%"
echo.
if not "%CODE%"=="0" (
  echo FALHA AO APLICAR A R11. Codigo: %CODE%
) else (
  echo R11 APLICADA. Abra o Godot e pressione F5.
)
pause
exit /b %CODE%
