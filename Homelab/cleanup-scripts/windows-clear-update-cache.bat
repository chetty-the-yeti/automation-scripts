@echo off
echo Stopping Windows Update service...
net stop wuauserv

echo Deleting Windows Update cache...
del /s /q /f %windir%\SoftwareDistribution\*

echo Starting Windows Update service...
net start wuauserv

echo Windows Update cache cleared successfully!
pause
