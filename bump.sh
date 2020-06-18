#!/bin/sh

if git status | grep -q 'modified:'; then
    echo "modified files detected, commit or stash and rerun"
    exit 1
fi 

DATE=`date +%y.%m.%d.1`

sed -i "s/ENV BUMP .*/ENV BUMP $DATE/" Dockerfile 
git stage Dockerfile
git commit -m "bump $DATE"
git push origin 12
git push origin master

