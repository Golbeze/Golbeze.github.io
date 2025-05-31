#!/bin/bash

if [[ "$#" -lt 1 ]];
then
    echo "usage $0 <title> <categories> <date>"
    echo "example : "
    echo "      $0 cve-2023-3079 v8 2023-08-14"
    exit 1
fi

echo "[*] find latest uploaded zip."
# change to working directory
cd _posts

# get latest filename and extract from zip
filename=$(ls -t | grep zip | head -n 1)
mdfilename="${filename%%.*}.md"

unzip -o -qq "$filename"  # force overwrite
mv ./imgs/* ../imgs/
rmdir ./imgs

mv "$filename" ./archive/


blog_date=$3
if [[ -z ${blog_date} ]];
then
    blog_date=$(echo "$filename" | grep -Eo '[[:digit:]]{4}-[[:digit:]]{2}-[[:digit:]]{2}')
    if [[ -z ${blog_date} ]];
    then
        mdfilename=$(../rename.sh "$mdfilename" "$(date '+%Y-%m-%d')")
        blog_date=$(date '+%Y-%m-%d %H:%M:%S %z') # today
        echo "[!] using current time: $blog_date"
    else
        blog_date="$blog_date 13:00:20 +0800"
    fi
else
    mdfilename=$(../rename.sh "$mdfilename" $blog_date)
    blog_date="$blog_date 13:00:20 +0800"
fi

title=$1
if [[ -z "${title}" ]];
then
    echo "title is required."
    exit 1
fi

categories="ctf"
if [[ -n "$2" ]];
then
    categories=$2
fi


read -r -d '' header << EOM
---
layout: post
EOM

header="$header"$'\n'
header="${header}title: \"$title\""$'\n'
header="${header}date: $blog_date"$'\n'
header="${header}categories: $categories"$'\n'
header="${header}---"$'\n'


content=$header

content="${header}$(cat $mdfilename)"
echo "$content" > $mdfilename

cd ..

