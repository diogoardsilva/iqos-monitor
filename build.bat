@echo off
rem Gera dist\IqosMonitor.exe localmente (Windows, Python 3.11+).
python -m pip install -r requirements.txt pyinstaller || exit /b 1
pyinstaller --noconfirm --onefile --windowed --name IqosMonitor --icon assets\icon.ico run.py
