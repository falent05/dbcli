cd "%~dp0"
set target=D:\green\github\dbcli
del /s "%target%\*.lua"
del /s "%target%\*.jar"
del /s "%target%\*.sql"
del /s "%target%\*.chm"
xcopy  . "%target%" /S /Y  /exclude:excludes.txt

COPY /Y "C:\Software\eclipse\workspace\dbcli\src\Loader.java" .\src\
COPY /Y .\src\Loader.java "%target%\src"
COPY /Y .\copy_to_git.bat "%target%\src"
pause
