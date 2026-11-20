@echo off
rem Builds bin\faimgraph.exe: upstream faimGraph library sources (GPUPeople/faimGraph @ d54a72e, unmodified unless
rem PORT_NOTES.md says otherwise) + bench_faim.cu driver, for sm_89 / CUDA 12.8 / MSVC 2022.
set "VCV=C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VCV%" set "VCV=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
if not exist "%VCV%" (echo vcvars64.bat not found & exit /b 1)
call "%VCV%" >nul
set H=%~dp0
set U=%H%upstream
if not exist "%H%..\..\bin" mkdir "%H%..\..\bin"
nvcc -O3 -std=c++17 -w -arch=sm_89 --expt-extended-lambda --expt-relaxed-constexpr -D_FORCE_INLINES -Xcompiler "/EHsc /bigobj" ^
  -I"%U%\include" -I"%U%\include\algorithms" ^
  "%H%bench_faim.cu" "%U%\src\Instantiations.cu" ^
  -x cu "%U%\src\COO.cpp" "%U%\src\CSR.cpp" "%U%\src\dCSR.cpp" "%U%\src\ConfigurationParser.cpp" "%U%\src\CSVWriter.cpp" ^
  "%U%\src\MemoryManager.cpp" "%U%\src\GraphParser.cpp" "%U%\src\Utility.cpp" "%U%\src\faimGraph.cpp" "%U%\src\EdgeUpdate.cpp" ^
  "%U%\src\VertexUpdate.cpp" -x none "%U%\src\SpMV.cu" "%U%\src\SpMM.cu" ^
  -o "%H%..\..\bin\faimgraph.exe"
