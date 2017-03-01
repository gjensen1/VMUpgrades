@echo off

reg query HKLM\Software\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell /v ExecutionPolicy

if ERRORLEVEL 1 goto not_exist
goto exit

:not_exist
reg add HKLM\Software\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell /v ExecutionPolicy /t REG_SZ /d RemoteSigned /f

:exit