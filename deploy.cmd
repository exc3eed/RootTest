@if "%SCM_TRACE_LEVEL%" NEQ "4" @echo off

:: ----------------------
:: KUDU Deployment Script
:: Version: 1.0.6
:: ----------------------

:: Prerequisites
:: -------------

:: Verify node.js installed
where node 2>nul >nul
IF %ERRORLEVEL% NEQ 0 (
  echo Missing node.js executable, please install node.js, if already installed make sure it can be reached from current environment.
  goto error
)

:: Setup
:: -----

setlocal enableextensions enabledelayedexpansion

SET SITEFOLDER=D:\home\site

SET xmlFile=%SITEFOLDER%\deployments\settings.xml
echo Reading %xmlFile%
for /f "tokens=* delims= " %%a in ('findstr /i /c:"branch" "%xmlFile%"') do (
    :: You should have something like this: <add value="develop" key="branch"/>
    echo Found branch entry: %%a 
    SET LINE=%%a
    :: Take the second through fifth tokens delimited by space or equal.
    for /f "tokens=2,3,4,5 delims== " %%c in ("%LINE%") do (
        IF "%%a"=="value" SET VALUE=%%b
        IF "%%c"=="value" SET VALUE=%%d
        IF NOT DEFINED VALUE SET VALUE=master
    )
    :: Remove surrounding quotes
    for /f "useback tokens=*" %%d in ('%VALUE%') do SET BRANCH=%%~d
)
echo Pulling from %BRANCH% branch.

SET ARTIFACTS=%~dp0%..\artifacts

IF NOT DEFINED DEPLOYMENT_SOURCE (
  SET DEPLOYMENT_SOURCE=%~dp0%.
)

IF NOT DEFINED NEXT_MANIFEST_PATH (
  SET NEXT_MANIFEST_PATH=%ARTIFACTS%\manifest

  IF NOT DEFINED PREVIOUS_MANIFEST_PATH (
    SET PREVIOUS_MANIFEST_PATH=%ARTIFACTS%\manifest
  )
)

:: Get the folder name for NEXT_MANIFEST_PATH and PREVIOUS_MANIFEST_PATH.  
:: We'll store our additional manifests in the NEXT_MANIFEST_FOLDER.
For %%A in ("%NEXT_MANIFEST_PATH%") DO SET NEXT_MANIFEST_FOLDER=%%~dpA
For %%A in ("%PREVIOUS_MANIFEST_PATH%") DO SET PREVIOUS_MANIFEST_FOLDER=%%~dpA
echo NEXT_MANIFEST_FOLDER %NEXT_MANIFEST_FOLDER%
echo PREVIOUS_MANIFEST_FOLDER %PREVIOUS_MANIFEST_FOLDER%
echo -----------------------------------------------------------

IF NOT DEFINED KUDU_SYNC_CMD (
  :: Install kudu sync
  echo Installing Kudu Sync
  call npm install kudusync -g --silent
  IF !ERRORLEVEL! NEQ 0 goto error

  :: Locally just running "kuduSync" would also work
  SET KUDU_SYNC_CMD=%appdata%\npm\kuduSync.cmd
)

IF NOT DEFINED DEPLOYMENT_TEMP (
  SET DEPLOYMENT_TEMP=%temp%\___deployTemp%random%
  SET CLEAN_LOCAL_DEPLOYMENT_TEMP=true
)

IF DEFINED CLEAN_LOCAL_DEPLOYMENT_TEMP (
  IF EXIST "%DEPLOYMENT_TEMP%" rd /s /q "%DEPLOYMENT_TEMP%"
  mkdir "%DEPLOYMENT_TEMP%"
)

IF DEFINED MSBUILD_PATH goto MsbuildPathDefined
SET MSBUILD_PATH=%ProgramFiles(x86)%\MSBuild\14.0\Bin\MSBuild.exe
:MsbuildPathDefined

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:: Deployment
:: ----------
SET EXTERNAL_REPO_URL=NULL
SET EXTERNAL_REPO_BRANCH=NULL

echo -----------------------------------------------------------
SET REPO_NAME=Site1Test
SET EXTERNAL_REPO_URL = https://github.com/exc3eed/Site1Test.git
SET NEXT_GOTO_LABEL=pull_temp-test-web-azure-slot-sync-site2
GOTO clone_or_pull

:pull_temp-test-web-azure-slot-sync-site2
echo -----------------------------------------------------------
SET REPO_NAME=TestSite2
SET EXTERNAL_REPO_URL = https://github.com/exc3eed/TestSite2.git
SET NEXT_GOTO_LABEL=deploy_temp-test-web-azure-slot-sync-root
GOTO clone_or_pull

:::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:deploy_temp-test-web-azure-slot-sync-root
echo -----------------------------------------------------------
:: The DEPLOYMENT_SOURCE is the External Repository Git url set in the Deployment Source panel.
:: NEXT_MANIFEST_PATH configured by Azure
:: PREVIOUS_MANIFEST_PATH configured by Azure

SET REPO_NAME=RootTest
SET DEPLOYMENT_TARGET=%SITEFOLDER%\wwwroot
SET NEXT_GOTO_LABEL=deploy_temp-test-web-azure-slot-sync-site1
GOTO basic_deployment

:deploy_temp-test-web-azure-slot-sync-site1
SET REPO_NAME=Site1Test
echo -----------------------------------------------------------
SET DEPLOYMENT_TARGET=%SITEFOLDER%\wwwroot\%REPO_NAME%
SET DEPLOYMENT_SOURCE=%SITEFOLDER%\%REPO_NAME%
SET NEXT_GOTO_LABEL=deploy_temp-test-web-azure-slot-sync-site2
GOTO basic_deployment

:deploy_temp-test-web-azure-slot-sync-site2
echo -----------------------------------------------------------
SET REPO_NAME=TestSite2
SET DEPLOYMENT_TARGET=%SITEFOLDER%\wwwroot\%REPO_NAME%
SET DEPLOYMENT_SOURCE=%SITEFOLDER%\%REPO_NAME%
SET NEXT_GOTO_LABEL=end
GOTO basic_deployment

::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::
:clone_or_pull

    IF %EXTERNAL_REPO_URL% NEQ NULL (
        SET REPO_URL=%EXTERNAL_REPO_URL%
        SET LOGFILE_URL=%EXTERNAL_REPO_URL%
        SET EXTERNAL_REPO_URL=NULL
    ) ELSE (
        SET LOGFILE_URL=%EXTERNAL_REPO_URL%
        SET REPO_URL= https://github.com/MiguelFernandez/%REPO_NAME%.git
    )
    IF %EXTERNAL_REPO_BRANCH% NEQ NULL (
        SET DEPLOY_BRANCH=%EXTERNAL_REPO_BRANCH%
        SET EXTERNAL_REPO_BRANCH=NULL
    ) ELSE (
        SET DEPLOY_BRANCH=%BRANCH%
    )
    IF NOT EXIST %SITEFOLDER%\%REPO_NAME% GOTO clone_repository
    cd /D %HOME%\site\%REPO_NAME%
    echo Pulling %LOGFILE_URL% %DEPLOY_BRANCH% into %CD%
    git pull %REPO_URL% %DEPLOY_BRANCH%
    goto DetailLogInfo
    
:clone_repository
    cd /D %HOME%\site
    echo Cloning %LOGFILE_URL% %DEPLOY_BRANCH% into %CD%
    git clone %REPO_URL% --branch %DEPLOY_BRANCH%
    goto DetailLogInfo

:project_build
    IF /I "%SOLUTION_FILENAME%" NEQ "" (
        echo Restore NuGet packages from %SOLUTION_PATH%
        call :ExecuteCmd nuget restore "%SOLUTION_PATH%"
        IF !ERRORLEVEL! NEQ 0 goto error
    )

    echo -----------------------------------------------------------

    echo Creating temporary deployment build folder %DEPLOYMENT_TEMP%
    IF DEFINED CLEAN_LOCAL_DEPLOYMENT_TEMP (
      IF EXIST "%DEPLOYMENT_TEMP%" rd /s /q "%DEPLOYMENT_TEMP%"
      mkdir "%DEPLOYMENT_TEMP%"
    )

    echo Build %REPO_NAME% application to the temporary path
    IF /I "%IN_PLACE_DEPLOYMENT%" NEQ "1" (
      call :ExecuteCmd "%MSBUILD_PATH%" "%PROJECT_PATH%" /nologo /verbosity:m /t:Build /t:pipelinePreDeployCopyAllFilesToOneFolder /p:_PackageTempDir="%DEPLOYMENT_TEMP%";AutoParameterizationWebConfigConnectionStrings=false;Configuration=Release;UseSharedCompilation=false /p:SolutionDir="%DEPLOYMENT_SOURCE%\.\\" %SCM_BUILD_ARGS%
    ) ELSE (
      call :ExecuteCmd "%MSBUILD_PATH%" "%PROJECT_PATH%" /nologo /verbosity:m /t:Build /p:AutoParameterizationWebConfigConnectionStrings=false;Configuration=Release;UseSharedCompilation=false /p:SolutionDir="%DEPLOYMENT_SOURCE%\.\\" %SCM_BUILD_ARGS%
    )

    IF !ERRORLEVEL! NEQ 0 goto error

    echo -----------------------------------------------------------

    SET DEPLOYMENT_SOURCE=%DEPLOYMENT_TEMP%

:basic_deployment
	SET NEXT_MANIFEST_PATH=%NEXT_MANIFEST_FOLDER%%REPO_NAME%
	SET PREVIOUS_MANIFEST_PATH=%PREVIOUS_MANIFEST_FOLDER%%REPO_NAME%

    IF /I "%IN_PLACE_DEPLOYMENT%" NEQ "1" (
      call :ExecuteCmd "%KUDU_SYNC_CMD%" -v 50 -f "%DEPLOYMENT_SOURCE%" -t "%DEPLOYMENT_TARGET%" -n "%NEXT_MANIFEST_PATH%" -p "%PREVIOUS_MANIFEST_PATH%" -i ".git;.hg;.deployment;deploy.cmd;*.exclude"
      IF !ERRORLEVEL! NEQ 0 goto error
    )
    goto %NEXT_GOTO_LABEL%

:DetailLogInfo
    SET taginfo=NULL
    SET numofcommits=5
    SET version=NULL
    
    @echo off
    ::Send std error from the git describe results to NULL.
    ::If an error occurs, we'll know it. Basically we are capturing errors like:
    ::fatal: No names found, cannot describe anything.
    ::If no errors occur, the tag will be shown in the log.
    ::A good reference: http://www.robvanderwoude.com/battech_redirection.php
    echo --- Tag Describe ---
    git describe --tags --candidates 1 2>NULL
    if errorlevel 1 goto Failed

    ::Get tag information from the git describe results.
    ::Format tag name, a hyphen, the number of commits made, a hyphen, the letter 'g' and then the commit identifier
    for /f %%i in ('git describe --tags --candidates 1') do SET taginfo=%%i

    goto GetNumOfCommits

    :Failed
    echo No tags were found.

    :GetNumOfCommits
    ::Get number of commits from taginfo.
    for /F "tokens=2 delims=-" %%a in ("%taginfo%") do (
      SET numofcommits=%%a
    )
    
    ::Get version from taginfo.
    for /F "tokens=1 delims=-" %%a in ("%taginfo%") do (
      SET version=%%a
    )
    
    IF %taginfo% NEQ NULL (
        echo --- Version ---
        echo %version%
        echo --- Number of Commits ---
        echo %numofcommits%
    )

    SET commitlimit=50
    IF %numofcommits% LEQ %commitlimit% (
        echo --- Last %numofcommits% Commit Messages ---
        git log --oneline --decorate -%numofcommits%
    ) ELSE (
        echo --- Last %commitlimit% Commit Messages ---
        git log --oneline --decorate -%commitlimit%
        echo Omitting next output lines...
    )
    goto %NEXT_GOTO_LABEL%
    
::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::::

:: Execute command routine that will echo out when error
:ExecuteCmd
setlocal
set _CMD_=%*
call %_CMD_%
if "%ERRORLEVEL%" NEQ "0" echo Failed exitCode=%ERRORLEVEL%, command=%_CMD_%
exit /b %ERRORLEVEL%

:error
endlocal
echo An error has occurred during web site deployment.
call :exitSetErrorLevel
call :exitFromFunction 2>nul

:exitSetErrorLevel
exit /b 1

:exitFromFunction
()

:end
endlocal
echo Finished successfully.