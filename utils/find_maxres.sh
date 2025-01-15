#!/bin/bash

max_width=0
max_height=0
max_file=""

for file in *.mp4; do
    # Extract width and height
    resolution=$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$file")
    width=$(echo "$resolution" | cut -d, -f1)
    height=$(echo "$resolution" | cut -d, -f2)

    # Compare with the current maximum
    if (( width * height > max_width * max_height )); then
        max_width=$width
        max_height=$height
        max_file=$file
    fi
done

echo "${max_width}x${max_height} from file: $max_file"
