# HOW TO RUN IMPORTER WITH MINIO

To run importer with minio we need to add this repository to mdm and map it ./ai folder

https://scm.devfactory.com/stash/scm/aurea-dfi/importers-scripts.git/?branch=minio-test  ->  ./ai/

Pay attention to the branch "minio-test", this branch has custom variables set so that minio works. These variables have to be set because they are not being passed as mdm parameter yet.

# BUILD COMMAND

We should setup in mdm the build commands as following

./ai/run.sh -ver minio -uja 1 -bc "gradle -p sources clean build -x test" 

Pay attention to "-ver" parameter. This is used to define which importers binaries should be fetched from the bas bucket, if it's not set the latest version will be fetched by default(latest does not support minio).

s3://aline-bas-bucket-prod/auto-importers/binaries/java-importer/$VERSION

Where $VERSION is equal to the version received with "-ver" parameter.

Inside this folder there is two scripts one is "run.sh" and another one is "run_hardcoded.sh"
The "run_hardcoded.sh" have some variables set to make it able to run on localhost without the need of aline.

Inside both scripts you will find that there are some variables that is hard coded, this is there until mdm start passing these as parameter. Please set them according to your environment configuration.

The variables to be set are STORAGE_PROVIDER, STORAGE_BUCKET, STORAGE_HOST, MINIO_ACCESS_KEY and MINIO_SECRET_ACCESS_KEY
Some variables have options, for example STORAGE_PROVIDER can be "S3", "MINIO" or "LOCAL". These options are inside script so just read
script and set them according to your needs.
