@echo off

set VERSION=1.9.1

set FOLDER_VERSION=latest
set IMPORTERS_BUCKET=aline-bas-bucket-prod
set IMPORTER_DIR=%~dp0
set SCRIPT_RETURN_CODE=0
set ACCEPT_GENERATED_FILES="false"
set PREVENT_DUPLICATE_SOURCES="false"

rem get values from command line arguments
:initial
if "%~1"=="" goto done

set aux=%~1
if "%aux:~0,1%"=="-" (
    if "%aux%" == "-e" set EXCLUSIONS=%~2
    if "%aux%" == "--exclusions" set EXCLUSIONS=%~2
    if "%aux%" == "-l" set LANGUAGES=%~2
    if "%aux%" == "--languages" set LANGUAGES=%~2
    if "%aux%" == "-l2" set LANGUAGES2=%~2
    if "%aux%" == "--languages2" set LANGUAGES2=%~2
    if "%aux%" == "-b" set BUILDSCRIPT=%~2
    if "%aux%" == "--buildscript" set BUILDSCRIPT=%~2
    if "%aux%" == "-uja" set USE_JAVA_AGENT=%~2
    if "%aux%" == "--useJavaAgent" set USE_JAVA_AGENT=%~2
    if "%aux%" == "-agf" set ACCEPT_GENERATED_FILES="true"
    if "%aux%" == "--acceptGeneratedFiles" set ACCEPT_GENERATED_FILES="true"
    if "%aux%" == "-pds" set PREVENT_DUPLICATE_SOURCES="true"
    if "%aux%" == "--preventDuplicatedSources" set PREVENT_DUPLICATE_SOURCES="true"
    if "%aux%" == "-bc" set BUILDCOMMAND=%~2
    if "%aux%" == "--buildcommand" set BUILDCOMMAND=%~2
  	if "%aux%" == "-una" set USE_NET_AGENT=%~2
  	if "%aux%" == "-noc" set NO_OVERRIDE_CONFIG=%~2
    if "%aux%" == "-no-bs" set BUILDSCORECARD="false"
    if "%aux%" == "--skipbuildscorecard" set BUILDSCORECARD="false"
    if "%aux%" == "-ver" set FOLDER_VERSION=%~2
    if "%aux%" == "--version" set FOLDER_VERSION=%~2
    if "%aux%" == "-cs" set CUSTOMER_SCRIPTS=%~2
    if "%aux%" == "--customerscripts" set CUSTOMER_SCRIPTS=%~2
)
shift
goto initial
:done

echo "Value of AWS_ACCESS_KEY_ID: %AWS_ACCESS_KEY_ID%"
echo "Value of AWS_SECRET_ACCESS_KEY: %AWS_SECRET_ACCESS_KEY%"
echo "Value of BUILD_PRODUCT_VERSIONID: %BUILD_PRODUCT_VERSIONID%"
echo "Value of BASE_DIR: %BASE_DIR%"
echo "Value of S3BUCKET: %S3BUCKET%"
echo "Value of DISABLE_OTHER_AGENTS: %DISABLE_OTHER_AGENTS%"
echo "=============== Command line args ==============="
echo "Value of USE_JAVA_AGENT: %USE_JAVA_AGENT%"
echo "Value of USE_NET_AGENT: %USE_NET_AGENT%"
echo "Value of NO_OVERRIDE_CONFIG : %NO_OVERRIDE_CONFIG%"
echo "Value of EXCLUSIONS: $%EXCLUSIONS%"
echo "Value of LANGUAGES: %LANGUAGES%"
echo "Value of LANGUAGES2: %LANGUAGES2%"
echo "Value of ACCEPT_GENERATED_FILES: %ACCEPT_GENERATED_FILES%"
echo "Value of BUILDSCRIPT: %BUILDSCRIPT%"
echo "Value of BUILDCOMMAND: %BUILDCOMMAND%"

echo "=============== Starting to copy importer binaries ==============="
aws s3 sync s3://%IMPORTERS_BUCKET%/auto-importers/binaries/%FOLDER_VERSION% %IMPORTER_DIR%
echo "=============== Finished copying importer binaries ==============="

if DEFINED CUSTOMER_SCRIPTS (
    echo "=============== Starting to copy %CUSTOMER_SCRIPTS% files to %BASE_DIR%\scripts ==============="
    mkdir %BASE_DIR%\scripts
    aws s3 sync s3://%IMPORTERS_BUCKET%/auto-importers/scripts/%CUSTOMER_SCRIPTS% %BASE_DIR%\scripts
    echo "=============== Finished copying %CUSTOMER_SCRIPTS% files to %BASE_DIR%\scripts ==============="
)


set FREEPORT=
set STARTPORT=1080

echo "Start searching free port"
:SEARCHPORT
netstat -o -n -a | find "LISTENING" | find ":%STARTPORT% " > NUL
if "%ERRORLEVEL%" equ "0" (
  echo "port unavailable %STARTPORT%"
  set /a STARTPORT +=1
  GOTO :SEARCHPORT
) ELSE (
  echo "port available %STARTPORT%"
  set FREEPORT=%STARTPORT%
  GOTO :FOUNDPORT
)
:FOUNDPORT
echo "Free port found: %FREEPORT%"

echo "Call DF_DISABLE_AGENTS to disable other agents"
call %DF_DISABLE_AGENTS%
set JAVA_TOOL_OPTIONS=

FOR /F "tokens=1 delims=/" %%G IN ("%AWS_S3_BUCKET%") DO (
    set S3BUCKET=%%G
)
set DF_PACKAGER_URL=http://localhost:%FREEPORT%
set PACKAGING_BASE_URI=s3://%S3BUCKET%
set ALINE_METAINF_JSON_FILE=%BASE_DIR%\logs\metainf\metainf.json
set MODULES_KEY=modules/

echo "Starting the packager (in test mode). PORT: %FREEPORT% testMode"
java -jar %IMPORTER_DIR%\dfbuild-packager-%VERSION%.jar --awsKey %AWS_ACCESS_KEY_ID% --awsSecret %AWS_SECRET_ACCESS_KEY% --port %FREEPORT% --testMode true --acceptGeneratedFiles %ACCEPT_GENERATED_FILES% --preventDuplicateSources %PREVENT_DUPLICATE_SOURCES%
if errorlevel 1 (
	echo "Starting packager FAILED, got return code: %ERRORLEVEL%"
	echo "Copy logs to %BASE_DIR%\logs folder"
    xcopy *.log logs\ /y
	echo "importer script completed FAIL"
	exit /B 1
) else (
    echo "Running packager in test mode was successful, so run it in normal mode now. PORT: %FREEPORT%"
    start "packager" java -jar %IMPORTER_DIR%\dfbuild-packager-%VERSION%.jar --awsKey %AWS_ACCESS_KEY_ID% --awsSecret %AWS_SECRET_ACCESS_KEY% --port %FREEPORT% --acceptGeneratedFiles %ACCEPT_GENERATED_FILES% --preventDuplicateSources %PREVENT_DUPLICATE_SOURCES%
)
echo "Sleeping for 10 secs..."
ping 127.0.0.1 -n 10 -w 1000 >NUL

if DEFINED LANGUAGES (
    echo "Calling generic importer for languages: %LANGUAGES%"
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    java -jar %IMPORTER_DIR%\dfbuild-agent-generic-%VERSION%.jar --languages %LANGUAGES% --packagerurl %DF_PACKAGER_URL%
    if errorlevel 1 (
        echo "Generic importer FAILED, got return code: %ERRORLEVEL%"
        echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        echo "Finished generic importer for languages: %LANGUAGES%"
        set SCRIPT_RETURN_CODE=1
        GOTO :SHUTDOWNPKG
    )
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo "Finished generic importer for languages: %LANGUAGES%"
) else (
    echo No LANGUAGES defined, skip this
)

set JAVA_TOOL_OPTIONS=-javaagent:%IMPORTER_DIR%\dfbuild-agent-java-interceptor-%VERSION%.jar=BUILD_BASE_DIR=%BASE_DIR%
set JAVA_TOOL_OPTIONS=%JAVA_TOOL_OPTIONS%,URL=%DF_PACKAGER_URL%

if DEFINED USE_JAVA_AGENT (
    echo "JAVA_TOOL_OPTIONS = %JAVA_TOOL_OPTIONS%"
) else (
    set JAVA_TOOL_OPTIONS=
)

set NET_BUILD_DIR=%IMPORTER_DIR%\dynamic\agent
echo "NET_BUILD_DIR = %NET_BUILD_DIR%"

if DEFINED NO_OVERRIDE_CONFIG (
setx OverrideConfig "false" /M
)

if DEFINED USE_NET_AGENT (
echo Start the Net build agent
%NET_BUILD_DIR%\DF.Build.Integration.Agent.exe /start
)

cd %BASE_DIR%
if DEFINED BUILDSCORECARD (
  echo skip BUILDSCORECARD profiling pre script
) else (
  echo "BUILDSCORECARD pre script is being invoked"
  echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
  cmd /C call %IMPORTER_DIR%\df-bs-pre-script.bat
  if errorlevel 1 (
      echo "BUILDSCORECARD pre script FAILED, got return code: %ERRORLEVEL%"
      echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
      echo "BUILDSCORECARD pre script invocation ended"
      set SCRIPT_RETURN_CODE=1
      GOTO :SHUTDOWNPKG
  )
  echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
  echo "BUILDSCORECARD pre script invocation ended"
)

cd %BASE_DIR%
if DEFINED BUILDSCRIPT (
    echo "%BUILDSCRIPT% script is being invoked"
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    cmd /C call "%BUILDSCRIPT%"
    if errorlevel 1 (
        echo "%BUILDSCRIPT% script FAILED, got return code: %ERRORLEVEL%"
        echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        echo "%BUILDSCRIPT% script invocation ended"
        set SCRIPT_RETURN_CODE=1
        GOTO :SHUTDOWNPKG
    )
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo "%BUILDSCRIPT% script invocation ended"
) else (
    echo No BUILDSCRIPT defined, skip this
)

cd %BASE_DIR%
if DEFINED BUILDCOMMAND (
    echo "%BUILDCOMMAND% command is executed"
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    cmd /C %BUILDCOMMAND%
    if errorlevel 1 (
        echo "%BUILDCOMMAND% command FAILED, got return code: %ERRORLEVEL%"
        echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        echo "Finished executing build command %BUILDCOMMAND%"
        set SCRIPT_RETURN_CODE=1
        GOTO :SHUTDOWNPKG
    )
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo "Finished executing build command %BUILDCOMMAND%"
) else (
    echo No BUILDCOMMAND defined, skip this
)

cd %BASE_DIR%
if DEFINED BUILDSCORECARD (
  echo skip BUILDSCORECARD profiling pre script
) else (
  echo "BUILDSCORECARD post script is being invoked"
  echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
  cmd /C call %IMPORTER_DIR%\df-bs-post-script.bat
  if errorlevel 1 (
      echo "BUILDSCORECARD post script FAILED, got return code: %ERRORLEVEL%"
      echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
      echo "BUILDSCORECARD post script invocation ended"
      set SCRIPT_RETURN_CODE=1
      GOTO :SHUTDOWNPKG
  )
  echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
  echo "BUILDSCORECARD post script invocation ended"
)

set JAVA_TOOL_OPTIONS=

cd %BASE_DIR%

if DEFINED EXCLUSIONS (
    echo Excluding folders listed in: %EXCLUSIONS%
    for /F "tokens=* delims=" %%i in (%EXCLUSIONS%) do (
      echo Excluding folder: %%i
      rd /Q /S %%i
    )
)

cd %BASE_DIR%

if DEFINED LANGUAGES2 (
    echo "Calling generic importer 2 for languages: %LANGUAGES2%"
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    java -jar %IMPORTER_DIR%\dfbuild-agent-generic-%VERSION%.jar --languages %LANGUAGES2% --packagerurl %DF_PACKAGER_URL%
    if errorlevel 1 (
        echo "Generic importer 2 FAILED, got return code: %ERRORLEVEL%"
        echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
        echo "Finished generic importer 2 for languages: %LANGUAGES2%"
        set SCRIPT_RETURN_CODE=1
        GOTO :SHUTDOWNPKG
    )
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo "Finished generic importer 2 for languages: %LANGUAGES2%"
) else (
    echo No LANGUAGES2 defined, skip this
)

:SHUTDOWNPKG

cd %BASE_DIR%
echo "Send request to packager to generate dynmodules.json and then shutdown packager"
echo "%DF_PACKAGER_URL%"
java -jar %IMPORTER_DIR%\dfbuild-shutdown-packager-%VERSION%.jar %DF_PACKAGER_URL%
if errorlevel 1 (
    echo "Packager shutdown FAILED, got return code: %ERRORLEVEL%"
    set SCRIPT_RETURN_CODE=1
)

echo "Copy logs to %BASE_DIR%\logs folder"
xcopy *.log logs\ /y

if DEFINED USE_NET_AGENT (
    echo Stop the Net build agent
    %NET_BUILD_DIR%\DF.Build.Integration.Agent.exe /stop
)

if %SCRIPT_RETURN_CODE% neq 0 (
    echo "importer script completed FAIL"
) else (
    echo "importer script completed OK"
)

exit /B %SCRIPT_RETURN_CODE%
