#!/bin/bash

export BASE_DIR=/opt/dfinstaller
VERSION=1.9.1
FOLDER_VERSION=latest
IMPORTERS_BUCKET=aline-bas-bucket
IMPORTER_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_RETURN_CODE=0
ACCEPT_GENERATED_FILES="false"
PREVENT_DUPLICATE_SOURCES="false"
#example usage
# for a php project: ./java-importer-linux.sh  -l php
# for a  java project: ./java-importer-linux.sh -uja=1 -b './source/build-tools/build-java-project.sh'
# for a  java project: ./java-importer-linux.sh -l cpp -b './source/build-tools/build-cpp-project.sh'

# Pass received parameters to variables
while [[ $# > 0 ]]
do
key="$1"

case $key in
    -e|--exclusions)
    EXCLUSIONS="$2"
    shift # past argument
    ;;
    -l|--languages)
    LANGUAGES="$2"
    shift # past argument
    ;;
    -l2|--languages2)
    LANGUAGES2="$2"
    shift # past argument
    ;;
    -no-bs|--skipbuildscorecard)
    BUILDSCORECARD="false"
    shift # past argument
    ;;
    -b|--buildscript)
    BUILDSCRIPT="$2"
    shift # past argument
    ;;
    -bc|--buildcommand)
    BUILDCOMMAND="$2"
    shift # past argument
    ;;
    -agf|--acceptGeneratedFiles)
    ACCEPT_GENERATED_FILES="true"
    shift # past argument
    ;;
     -pds|--preventDuplicateSources)
    PREVENT_DUPLICATE_SOURCES="true"
    shift # past argument
    ;;
    -uja|--useJavaAgent)
    USE_JAVA_AGENT="$2"
    shift # past argument
    ;;
    -ver|--version)
    FOLDER_VERSION="$2"
    shift # past argument
    ;;
    -cs|--customerscripts)
    CUSTOMER_SCRIPTS="$2"
    shift # past argument
    ;;
    *)
    # unknown option
    ;;
esac
shift # past argument or value
done

function checkresult {
    STATUS_LAST_CMD=$?
    if [ $STATUS_LAST_CMD -ne 0 ]; then
        cd $BASE_DIR
        java -jar $IMPORTER_DIR/dfbuild-shutdown-packager-${VERSION}.jar "$DF_PACKAGER_URL"
        echo "Error message: \"$1\". Error Code: $STATUS_LAST_CMD "
        echo "Copying logs to $BASE_DIR/logs folder"
        cp -r $BASE_DIR/*.log $BASE_DIR/logs
        echo "Importer script finished with FAILURE"
        exit 1
    fi
}

aws configure set default.s3.signature_version s3v4
export ALINE_STORAGE_ENDPOINT_URL="http://minio-server-dev.us-east-1.elasticbeanstalk.com"
export BASE_DIR=/opt/dfinstaller
export ALINE_METAINF_JSON_FILE=$BASE_DIR/logs/metainf/metainf.json
export AWS_ACCESS_KEY_ID="$ALINE_STORAGE_ACCESS_KEY"
export AWS_SECRET_ACCESS_KEY="$ALINE_STORAGE_SECRET_KEY"
export AWS_DEFAULT_REGION=us-east-1

echo "Value of AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID"
echo "Value of AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY"
echo "Value of BUILD_PRODUCT_VERSIONID: $BUILD_PRODUCT_VERSIONID"
echo "Value of BASE_DIR: $BASE_DIR"
echo "Value of S3BUCKET: $S3BUCKET"
echo "Value of DISABLE_OTHER_AGENTS: $DISABLE_OTHER_AGENTS"
echo "=============== Command line args ==============="
echo "Value of USE_JAVA_AGENT: $USE_JAVA_AGENT"
echo "Value of EXCLUSIONS: $EXCLUSIONS"
echo "Value of LANGUAGES: $LANGUAGES"
echo "Value of LANGUAGES2: $LANGUAGES2"
echo "Value of ACCEPT_GENERATED_FILES: $ACCEPT_GENERATED_FILES"
echo "Value of BUILDSCRIPT: $BUILDSCRIPT"
echo "Value of BUILDCOMMAND: $BUILDCOMMAND"

echo "=============== Starting to copy importer binaries ==============="
aws --endpoint-url "$ALINE_STORAGE_ENDPOINT_URL" s3 sync "s3://${IMPORTERS_BUCKET}/auto-importers/binaries/java-importer/${FOLDER_VERSION}" "${IMPORTER_DIR}"
chmod -R 777 ${IMPORTER_DIR}
echo "=============== Finished copying importer binaries ==============="

if [ ! -z "$CUSTOMER_SCRIPTS" ]; then
    echo "=============== Starting to copy ${CUSTOMER_SCRIPTS} files to ${BASE_DIR}/scripts ==============="
    mkdir -p $BASE_DIR/scripts
    aws --endpoint-url "$ALINE_STORAGE_ENDPOINT_URL" s3 sync "s3://${IMPORTERS_BUCKET}/auto-importers/scripts/${CUSTOMER_SCRIPTS}" "$BASE_DIR/scripts"
    chmod -R 777 $BASE_DIR/scripts
    echo "=============== Finished copying ${CUSTOMER_SCRIPTS} files to ${BASE_DIR}/scripts ==============="
fi

# Make sure logs folder is created
if [ ! -d "logs" ]; then
    mkdir logs
fi

## Find an available port
echo "Start searching free port"
export PORT="$(ss -tln | awk 'NR > 1{gsub(/.*:/,"",$4); print $4}' | sort -un | awk -v n=1080 '$0 < n {next}; $0 == n {n++; next}; {exit}; END {print n}')"
echo "Free port found: $PORT"

## Disable other agents
##
echo "Call DF_DISABLE_AGENTS to disable other agents"
$DF_DISABLE_AGENTS

#Export variables that are necessary for the generic agent
# S3 BUCKET WILL BE DEPRECATED WHEN ALINE START PASSING $STORAGE_PROVIDER JUST WITH BUCKET NAME, SO WE WON'T NEED TO PARSE STRING ANYMORE
S3BUCKET=$(echo $AWS_S3_BUCKET | awk -F / '{ print $1 }');
export DF_PACKAGER_URL="http://localhost:$PORT"
export ALINE_METAINF_JSON_FILE=$BASE_DIR/logs/metainf/metainf.json
export ENCODING="UTF8";

# WARNING THESE VARIABLES SHOULD COME ON MDM, I'M JUST SETTING HERE FOR TESTING PURPOSES
# S3 | MINIO | LOCAL
export STORAGE_PROVIDER="MINIO"
# THIS IS THE NAME OF THE BUCKET, eg s3 -> s3://aline-build-output-p9  | minio -> http://127.0.0.1:9000/minio/aline-build-output-p9
# IN EITHER CASE THIS VARIABLE SHOULD BE SET AS "aline-build-output-p9". CURRENTLY MDM GIVE US $AWS_S3_BUCKET, THIS SHOULD BE
# CHANGED TO STORAGE_BUCKET TO WORK FOR BOTH S3 AND MINIO
export STORAGE_BUCKET="aline-build-output-d9"
# THIS VARIABLE ONLY NEEDS TO BE SET WHEN STORAGE_PROVIDER=MINIO , IN CASE OF S3 THIS CAN REMAIN EMPTY!
# THIS SHOULD COME AS MDM PARAMETER, IT'S HARD CODED TO TEST ON LOCALHOST, BUT SHOULD BE CHANGED TO ANOTHER IP IN CASE MINIO IS NOT RUNNING LOCALLY
#export STORAGE_HOST="http://127.0.0.1:9000"
# MINIO GENERATED KEYS, SHOULD COME AS MDM PARAMETER, HARD CODED FOR TESTING PURPOSES, SET IT ACCORDING TO YOUR ENVIRONMENT
#export STORAGE_ACCESS_KEY_ID="8P4XJ82BN1LPTMUCVR1Y"
#export STORAGE_SECRET_ACCESS_KEY="M31UrmDqoRjHq6PHumHcaILGNgykU/hi3GgfOZbD"


# Aline addins for storage settings
if [ "$ALINE_STORAGE_BACKEND_TYPE" = "AWS_S3" ]; then
    export STORAGE_PROVIDER="S3"
fi

export STORAGE_BUCKET="http://minio-server-dev.us-east-1.elasticbeanstalk.com/minio/aline-build-output-d9/"
export STORAGE_HOST="$ALINE_STORAGE_ENDPOINT_URL"
export STORAGE_ACCESS_KEY_ID="$ALINE_STORAGE_ACCESS_KEY"
export STORAGE_SECRET_ACCESS_KEY="$ALINE_STORAGE_SECRET_KEY"
export S3BUCKET=aline-build-output-d9
export MINIO_BUCKET=aline-build-output-d9
export MINIO_HOST="$ALINE_STORAGE_ENDPOINT_URL"
export MINIO_ACCESS_KEY_ID="$ALINE_STORAGE_ACCESS_KEY"
export MINIO_SECRET_ACCESS_KEY="$ALINE_STORAGE_SECRET_KEY"

echo "==================VALUES=============="

echo "STORAGE_BUCKET=\"$STORAGE_BUCKET\""
echo "STORAGE_HOST=\"$STORAGE_HOST\""
echo "STORAGE_ACCESS_KEY_ID=\"$STORAGE_ACCESS_KEY_ID\""
echo "STORAGE_SECRET_ACCESS_KEY=\"$STORAGE_SECRET_ACCESS_KEY\""

## Start the packager
# set JAVA_TOOL_OPTIONS empty, there can be some problem here which can break packager
unset JAVA_TOOL_OPTIONS
echo "Starting the packager (in test mode). PORT: $PORT testMode"
java -jar $IMPORTER_DIR/dfbuild-packager-${VERSION}.jar --awsKey "$AWS_ACCESS_KEY_ID" --awsSecret "$AWS_SECRET_ACCESS_KEY" --port "$PORT" --testMode true --acceptGeneratedFiles "$ACCEPT_GENERATED_FILES" --preventDuplicateSources "$PREVENT_DUPLICATE_SOURCES" || { echo "Starting packager in testMode FAILED"; exit 1; }

echo "Running packager in test mode was successful, so run it in normal. Port: $PORT"
java -jar $IMPORTER_DIR/dfbuild-packager-${VERSION}.jar --awsKey "$AWS_ACCESS_KEY_ID" --awsSecret "$AWS_SECRET_ACCESS_KEY" --port "$PORT" --acceptGeneratedFiles "$ACCEPT_GENERATED_FILES" --preventDuplicateSources "$PREVENT_DUPLICATE_SOURCES" &

echo "Sleeping for 10 secs..."
sleep 10

if [ ! -z "$LANGUAGES" ]; then
    echo "Calling generic importer for languages: $LANGUAGES"
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    java -jar $IMPORTER_DIR/dfbuild-agent-generic-${VERSION}.jar --languages "$LANGUAGES" --packagerurl "$DF_PACKAGER_URL"
    checkresult "Invokation of Generic Importer for languages \"$LANGUAGES\" FAILED"
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo "Finished generic importer for languages: $LANGUAGES"
else
    echo "No LANGUAGES defined, skipping Generic Importer"
fi

JAVA_TOOL_OPTIONS="-javaagent:$IMPORTER_DIR/dfbuild-agent-java-interceptor-${VERSION}.jar=BUILD_BASE_DIR=$BASE_DIR";
JAVA_TOOL_OPTIONS+=",URL=$DF_PACKAGER_URL";
JAVA_TOOL_OPTIONS+=" -Dfile.encoding=$ENCODING";

if [ ! -z "$USE_JAVA_AGENT" ]; then
    export JAVA_TOOL_OPTIONS="$JAVA_TOOL_OPTIONS";
    echo "JAVA_TOOL_OPTIONS = $JAVA_TOOL_OPTIONS"
fi

# Call build scorecard pre script
if [ -z "$BUILDSCORECARD" ]; then
    echo "BUILDSCORECARD pre script is being invoked"
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    source $IMPORTER_DIR/df-bs-pre-script.sh
    checkresult "Execution of df-bs-pre-script FAILED"
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo "BUILDSCORECARD pre script invocation ended"
fi

# Call product build script received as parameter
if [ ! -z "$BUILDSCRIPT" ]; then
    echo "$BUILDSCRIPT script is being invoked"
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    source $BUILDSCRIPT
    checkresult "Execution of \"$BUILDSCRIPT\" script FAILED"
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo "$BUILDSCRIPT script invocation ended"
else
    echo "No BUILDSCRIPT defined, skip this"
fi

# Call product build command received as parameter
if [ ! -z "$BUILDCOMMAND" ]; then
    echo "Executing build command $BUILDCOMMAND"
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    eval $BUILDCOMMAND
    checkresult "Execution of build command \"$BUILDCOMMAND\" FAILED"
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo "Build command \"$BUILDCOMMAND\" executed FINE"
else
    echo "No BUILDCOMMAND defined, skip this"
fi

# Call build scorecard post script
if [ -z "$BUILDSCORECARD" ]; then
    echo "BUILDSCORECARD post script is being invoked"
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    source $IMPORTER_DIR/df-bs-post-script.sh
    checkresult "Execution of df-bs-post-script FAILED"
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo "BUILDSCORECARD post script invocation ended"
fi

# set JAVA_TOOL_OPTIONS empty, we do not need it anymore
unset JAVA_TOOL_OPTIONS

cd $BASE_DIR

# Removes all folders specified on parameter file(file containing one folder per line to be excluded)
if [ ! -z "$EXCLUSIONS" ]; then
    echo "Excluding folders listed in: $EXCLUSIONS"
    while read line
        do echo "Excluding folder: $line" && rm -rf "$line";
    done <$EXCLUSIONS
fi

cd $BASE_DIR

if [ ! -z "$LANGUAGES2" ]; then
    echo "Calling generic importer 2 for languages: $LANGUAGES2"
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    java -jar $IMPORTER_DIR/dfbuild-agent-generic-${VERSION}.jar --languages "$LANGUAGES2" --packagerurl "$DF_PACKAGER_URL"
    checkresult "Invocation of Generic Importer 2 for languages \"$LANGUAGES2\" FAILED"
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo "Finished generic importer 2 for languages: $LANGUAGES2"
else
    echo "No LANGUAGES2 defined, skipping Generic Importer 2"
fi

echo "Send request to packager to generate dynmodules.json and then shutdown packager"
echo "$DF_PACKAGER_URL"
java -jar $IMPORTER_DIR/dfbuild-shutdown-packager-${VERSION}.jar "$DF_PACKAGER_URL"
checkresult "Invokation of Shutdown Packager with \"$DF_PACKAGER_URL\" endpoint FAILED"

echo "Copying logs to $BASE_DIR/logs folder"
cp -r $BASE_DIR/*.log $BASE_DIR/logs
checkresult "Error copying logs, \"cp -r $BASE_DIR/*.log $BASE_DIR/logs\""

echo "Importers script completed SUCCESSFULLY"
