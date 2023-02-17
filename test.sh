#!/bin/bash
find ./bin -path ./bin/tmp -prune -o -type f -exec shellcheck -x {} +
find ./support -type f -exec shellcheck -x {} +
