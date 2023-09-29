#!/bin/bash

# exit on failures
set -e
set -o pipefail

usage() {
  echo "Usage: $(basename "$0") [OPTIONS]" 1>&2
  echo "  -h                     - help"
  echo "  -i <input_file>        - Input File"
  echo "  -r <replace_file>      - Replace File"
  echo "  -o <output_file>       - Output File"
  exit 1
}

# if there are no arguments passed exit with usage
if [ $# -lt 1 ]; then
  usage
fi

SCRIPT_PATH="$( cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

while getopts "i:o:r:h" opt; do
  case $opt in
    i)
      INPUT_FILE=$OPTARG
      ;;
    o)
      OUTPUT_PATH=$OPTARG
      ;;
    r)
      REPLACE_FILE=$OPTARG
      ;;
    h)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

echo "Munging $REPLACE_FILE with replacements:"
cat "$REPLACE_FILE"

docker build -f "$SCRIPT_PATH/Dockerfile.php-sql-munge" -t php-sql-munge .

docker run -v "$INPUT_FILE":/"$(basename "$INPUT_FILE")" \
  -v "$REPLACE_FILE":/replace.txt \
  -v "$OUTPUT_PATH":/output \
  php-sql-munge /bin/bash -c \
  "munge /$(basename "$INPUT_FILE") && fix-serialization /munged.sql && mv /munged.sql /output/$(basename "$INPUT_FILE")"

echo "Munge and serializtion fixed!"
echo "Output stored in $OUTPUT_PATH/$(basename "$INPUT_FILE")"
