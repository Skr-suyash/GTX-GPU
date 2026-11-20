@echo off
rem Usage: build.bat <name>   (compiles src\<name>.cu -> bin\<name>.exe)
rem Needs MSVC (VS 2022 Community or Build Tools, C++ workload) + CUDA 12.8.
set "VCV=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VCV%" set "VCV=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VCV%" set "VCV=C:\Program Files\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VCV%" (echo vcvars64.bat not found - install VS 2022 Build Tools with the C++ workload & exit /b 1)
call "%VCV%" >nul
if not exist "%~dp0bin" mkdir "%~dp0bin"
nvcc -O3 -std=c++17 -arch=sm_89 -lineinfo -Xcompiler "/O2 /EHsc" -I"%~dp0src" "%~dp0src\%1.cu" -o "%~dp0bin\%1.exe"
