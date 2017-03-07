#!/bin/bash

VERSION=1.9.1
FOLDER_VERSION=latest
IMPORTERS_BUCKET=aline-bas-bucket-prod
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
    -l|--languages)
    LANGUAGES="$2"
    shift # past argument
    ;;
    -no-bs|--skipbuildscorecard)
    BUILDSCORECARD="false"
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

if [ -z "$ALINE_STORAGE_BACKEND_TYPE" ]; then
    export ALINE_STORAGE_BACKEND_TYPE="AWS_S3"
elif [ "$ALINE_STORAGE_BACKEND_TYPE" = "MINIO" ]; then
    echo "Minio provider selected, setting default.s3.signature_version to s3v4"
    aws configure set default.s3.signature_version s3v4
    aws configure set default.region us-east-1
    ENDPOINT_PARAM="--endpoint-url ${ALINE_STORAGE_ENDPOINT_URL}"
fi
export AWS_S3_BUCKET="s3://$(echo $AWS_S3_BUCKET | awk -F / '{ print $1 }')"

echo "=============== Starting to copy importer binaries ==============="
aws ${ENDPOINT_PARAM} s3 sync s3://${IMPORTERS_BUCKET}/auto-importers/binaries/java-importer/${FOLDER_VERSION} ${IMPORTER_DIR}
chmod -R 777 ${IMPORTER_DIR}
echo "=============== Finished copying importer binaries ==============="

if [ ! -z "$CUSTOMER_SCRIPTS" ]; then
    echo "=============== Starting to copy ${CUSTOMER_SCRIPTS} files to ${BASE_DIR}/scripts ==============="
    mkdir -p $BASE_DIR/scripts
    aws ${ENDPOINT_PARAM} s3 sync s3://${IMPORTERS_BUCKET}/auto-importers/scripts/${CUSTOMER_SCRIPTS} $BASE_DIR/scripts
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

# Export variables that are necessary for the generic agent
export DF_PACKAGER_URL="http://localhost:$PORT"
export ALINE_METAINF_JSON_FILE=$BASE_DIR/logs/metainf/metainf.json
export ENCODING="UTF8";

echo "=============== Command line args ==============="
echo "Value of BUILD_PRODUCT_VERSIONID: $BUILD_PRODUCT_VERSIONID"
echo "Value of BASE_DIR: $BASE_DIR"
echo "Value of AWS_S3_BUCKET: $AWS_S3_BUCKET"
echo "Value of DISABLE_OTHER_AGENTS: $DISABLE_OTHER_AGENTS"
echo "Value of USE_JAVA_AGENT: $USE_JAVA_AGENT"
echo "Value of LANGUAGES: $LANGUAGES"
echo "Value of ACCEPT_GENERATED_FILES: $ACCEPT_GENERATED_FILES"
echo "Value of BUILDCOMMAND: $BUILDCOMMAND"
echo "Value of FOLDER_VERSION: $FOLDER_VERSION"
echo "Value of ALINE_STORAGE_BACKEND_TYPE: $ALINE_STORAGE_BACKEND_TYPE"
echo "Value of ALINE_STORAGE_ENDPOINT_URL: $ALINE_STORAGE_ENDPOINT_URL"
echo "Value of ALINE_STORAGE_BUCKET: $ALINE_STORAGE_BUCKET"

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
    source $IMPORTER_DIR/df-bs-post-script.sh ${ENDPOINT_PARAM}
    checkresult "Execution of df-bs-post-script FAILED"
    echo "+++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++"
    echo "BUILDSCORECARD post script invocation ended"
fi

# set JAVA_TOOL_OPTIONS empty, we do not need it anymore
unset JAVA_TOOL_OPTIONS
cd $BASE_DIR

echo "Send request to packager to generate dynmodules.json and then shutdown packager"
echo "$DF_PACKAGER_URL"
java -jar $IMPORTER_DIR/dfbuild-shutdown-packager-${VERSION}.jar "$DF_PACKAGER_URL"
checkresult "Invokation of Shutdown Packager with \"$DF_PACKAGER_URL\" endpoint FAILED"

echo "Copying logs to $BASE_DIR/logs folder"
cp -r $BASE_DIR/*.log $BASE_DIR/logs
checkresult "Error copying logs, \"cp -r $BASE_DIR/*.log $BASE_DIR/logs\""

echo "Importers script completed SUCCESSFULLY"
