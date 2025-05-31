#!/bin/bash

if [[ "$#" -lt 1 ]];
then
    echo "usage: $0 <filename>"
    exit 1
fi

new="$2-$(echo "$1" | sed -r 's/[ _]+/-/g')"

mv "$1" $new
echo $new
