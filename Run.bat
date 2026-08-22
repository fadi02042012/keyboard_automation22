@echo off
setlocal

title Flutter Build

echo ========================================
echo        STEP 1 - FLUTTER CLEAN
echo ========================================
call flutter clean
if errorlevel 1 goto ERROR

echo.
echo تم الانتهاء من الخطوة 1
timeout /t 3 /nobreak >nul


echo ========================================
echo        STEP 2 - FLUTTER PUB GET
echo ========================================
call flutter pub get
if errorlevel 1 goto ERROR

echo.
echo تم الانتهاء من الخطوة 2
timeout /t 3 /nobreak >nul


echo ========================================
echo        STEP 3 - FLUTTER ANALYZE
echo ========================================
call flutter analyze
if errorlevel 1 goto ERROR

echo.
echo تم الانتهاء من الخطوة 3
timeout /t 3 /nobreak >nul


echo ========================================
echo        STEP 4 - FLUTTER TEST
echo ========================================
call flutter test
if errorlevel 1 goto ERROR

echo.
echo تم الانتهاء من الخطوة 4
timeout /t 3 /nobreak >nul


echo ========================================
echo        STEP 5 - BUILD WINDOWS
echo ========================================
call flutter build windows --release
if errorlevel 1 goto ERROR

echo.
echo ========================================
echo BUILD SUCCESSFUL
echo ========================================
timeout /t 5 /nobreak >nul


echo ========================================
echo        STEP 6 - RUN WINDOWS
echo ========================================
call flutter run -d windows

echo.
echo ========================================
echo انتهى تشغيل التطبيق
echo ========================================
pause
goto END


:ERROR
echo.
echo ========================================
echo              ERROR
echo ========================================
echo حدث خطأ في الأمر السابق.
echo تم إيقاف العملية.
echo ========================================
echo.
pause
goto END


:END
echo.
echo اضغط أي مفتاح للخروج...
pause >nul