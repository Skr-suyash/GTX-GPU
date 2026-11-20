@echo off
rem GTX-GPU demo startup. Double-click, or run from any terminal.
rem Checks the GPU and binaries, then shows a menu of the benchmarks on slides 13 and 14.
cd /d "%~dp0"
title GTX-GPU demo
echo ==============================================================
echo  GTX-GPU demo   (folder: %cd%)
echo ==============================================================
nvidia-smi --query-gpu=name,memory.used,memory.total,utilization.gpu --format=csv,noheader
if errorlevel 1 (echo ERROR: nvidia-smi failed - is the NVIDIA driver running? & pause & exit /b 1)
where python >nul 2>nul
if errorlevel 1 (echo ERROR: python not found on PATH & pause & exit /b 1)
if not exist bin\bench.exe (
  echo bin\bench.exe missing - building, about 1 minute...
  call build.bat bench
)
if not exist bin\test_gtx.exe (
  echo bin\test_gtx.exe missing - building, about 1 minute...
  call build.bat test_gtx
)
if not exist bin\bench.exe (echo ERROR: build failed - see DEMO_COMMANDS.txt section 6 & pause & exit /b 1)
echo Warming up the GPU...
bin\bench.exe --sys gtx --label warmup --reps 1 --V 65536 --N 65536 --K 1 --pins 1 >nul
echo Ready.

:menu
echo.
echo  --- Slide 13: throughput and abort ratio (GTX-GPU vs GTX rules) ---
echo   1  Uniform inserts, K=32     (the 1.8x and 45%% to 0%% result)   ~10 s
echo   2  50%% hub inserts, K=32     (the 1.3x result)                 ~10 s
echo   3  Uniform inserts, K=8                                        ~10 s
echo   4  50%% hub inserts, K=8                                        ~10 s
echo   5  Uniform inserts, K=1      (the 181 M inserts/s point)       ~10 s
echo  --- Slide 14: mixed read/write transactions ---
echo   6  Mixed, uniform            7  Mixed, 50%% hub        8  Mixed, Zipf
echo   9  Insert/delete churn, K=1  (uniform and R-MAT)
echo  --- Correctness ---
echo   c  Run verified by the history checker                         ~15 s
echo   m  Write-skew probe + broken-protocol tests (checker must catch them)  ~2 min
echo   s  Show the saved 48-history correctness suite result
echo  --- Other ---
echo   r  Show recorded results for slides 13 and 14 (no GPU run)
echo   a  Run everything on slides 13 and 14                          ~2 min
echo   q  Quit
set "c="
set /p c=Choice:
if /i "%c%"=="1" python scripts\demo.py k32-uniform
if /i "%c%"=="2" python scripts\demo.py k32-hub
if /i "%c%"=="3" python scripts\demo.py k8-uniform
if /i "%c%"=="4" python scripts\demo.py k8-hub
if /i "%c%"=="5" python scripts\demo.py k1-uniform
if /i "%c%"=="6" python scripts\demo.py mixed-uniform
if /i "%c%"=="7" python scripts\demo.py mixed-hub
if /i "%c%"=="8" python scripts\demo.py mixed-zipf
if /i "%c%"=="9" (python scripts\demo.py churn-uniform & python scripts\demo.py churn-rmat)
if /i "%c%"=="c" python scripts\demo.py checked --reps 1
if /i "%c%"=="m" bin\test_gtx.exe full none
if /i "%c%"=="s" (findstr /c:"as expected" results\correctness_suite.txt | find /c /v "" & findstr /c:"RESULT" /c:"witnessed" /c:"UNEXPECTED" results\correctness_suite.txt)
if /i "%c%"=="r" findstr /r /c:"^uniform-ins-K[0-9]*,gtx" /c:"^hub50-ins-K[0-9]*,gtx" /c:"^SI-.*-rw-K4,gtx," /c:"churn-K1,gtx," /c:"^label" results\summary.csv
if /i "%c%"=="a" (for %%s in (k1-uniform k8-uniform k32-uniform k8-hub k32-hub mixed-uniform mixed-hub mixed-zipf churn-uniform churn-rmat) do python scripts\demo.py %%s)
if /i "%c%"=="q" exit /b 0
goto menu
