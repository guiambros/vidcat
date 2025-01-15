#!/bin/bash

# -- encoding parameters
FRAMERATE=30000/1001     # 29.97 fps. Should match the input videos being concatenated
NVIDIA_GPU=1             # enable nvidia GPU support. Test w/ ffmpeg -i in.mp4 -c:v h264_nvenc -preset fast -b:v 5M out.mp4
VIDEO_FORMAT="mp4"       # default video format. This was only tested with mp4, so proceed with caution

# -- cover page
INTRO_DURATION=8         # duration (in sec) for each episode cover page. Longer duration makes it easier to find when fast-seeking
FONT_FILE="wargames.ttf" # use a specific font, or leave it blank for default. Source: https://www.1001fonts.com/wargames-font.html
FONT_SIZE_L1=38          # line 1 (chapter title)
FONT_SIZE_L2=56          # line 2 (episode title)
MAX_LINE_LEN_L1=50       # max number of characters per line. This depends on font type and size above, so YMMV. Sane values:
MAX_LINE_LEN_L2=34       # fontsize 28: 70 chars, fontsize 38: 50 chars, fontsize 46: 42 chars, fontsize 56: 34 chars 
FONT_COLOR_L1="white"    # line 1; also accepts RGA (FF5733) or RGBA (FF573380)
FONT_COLOR_L2="FF7711EE" # line 2; also accepts RGA (FF5733) or RGBA (FF573380)
BG_COLOR="111111"        # cover page background color

# -- Output video resolution.
# Higher resolution means more quality, but large files. Strongly recommended to use the highest resolution of videos segments
# inside each chapter / subdirectory. Investigate with:
#     ffprobe -i input.mp4 -show_streams -pretty
#ASPECT_RATIO="640:360"
#BITRATE="300k"
ASPECT_RATIO="1280:720"
BITRATE="500k"

# -- in-memory virtual disk (note: requires sudo and available RAM)
USE_VIRTUAL_DISK=1       # create a virtual disk in memory. Faster, but requires enough RAM to hold all the files. Default off.
VIRTUAL_DISK_SIZE=6      # virtual disk size, in GB. Must be big enough to hold an entire chapter videos. Default: 2GB

# -- debug parameters
FFMPEG_VERBOSE=0         # if you have problems, enable ffmpeg output to see warnings/errors
#set -x                  # use for script for debugging


# ---------------------------------------------------------------------------------------------------------------------
# You shouldn't need to edit anything else beyond this line
#
if [[ $# -lt 1 || $# -gt 2 ]]; then
    echo "Usage: $(basename $0) <folder>, where folder contains all the subdirectories with videos to concatenate"
    echo
    echo "Note: each subdirectory inside <folder> will be used as chapter names, so this script expects these"
    echo "subdirectories to exist, and to contain one or more *.${VIDEO_FORMAT} videos."
    echo
    exit 1
else
    SOURCE_PATH="$1"
fi

if [[ $# -eq 2 ]]; then
    OUTPUT_PATH="$2"
else
    OUTPUT_PATH="."
fi

if [[ ! -d "${SOURCE_PATH}" ]]; then
    echo "Error: the input subdirectory '${SOURCE_PATH}' does not exist."
    exit 1
fi

if [[ ! -d "${OUTPUT_PATH}" ]]; then
    echo "Error: the output subdirectory '${OUTPUT_PATH}' does not exist."
    exit 1
fi

total_files=$(find "${SOURCE_PATH}" -name "*.${VIDEO_FORMAT}" | wc -l)
if [[ ${total_files} -eq 0 ]]; then
    echo "Error: the input subdirectory '${SOURCE_PATH}' does not contain any ${VIDEO_FORMAT} videos."
    exit 1
fi

if [[ "${FFMPEG_VERBOSE}" -eq "0" ]]; then
    DEBUG="-loglevel quiet"
else
    echo "Debug enabled; verbose mode"
    DEBUG=""
fi

if [[ "${NVIDIA_GPU}" -eq "1" ]]; then
    echo "GPU acceleration enabled"
    ENCODER="h264_nvenc"
    HW_ACCEL="-hwaccel cuda"
    VF_SCALE="hwupload,scale_cuda"
    PROFILE_PRESET="fast"
    CRF=""
else
    ENCODER="libx264"
    PROFILE_PRESET="veryfast"
    VF_SCALE="scale"
    CRF="-crf 23"
fi

TEMP_DIR="temp"
mkdir -p "${TEMP_DIR}"
if [[ "${USE_VIRTUAL_DISK}" -eq "1" ]]; then
    echo "Virtual disk enabled"
    sudo mount -t tmpfs -o size=${VIRTUAL_DISK_SIZE}G tmpfs ${TEMP_DIR}
fi

cleanup() {
    echo "Cleaning up temporary files..."
    if [[ "${USE_VIRTUAL_DISK}" -eq "1" ]]; then
        sudo umount "${TEMP_DIR}"
        rmdir "${TEMP_DIR}"
    else
        rmdir "${TEMP_DIR}"
    fi
    echo "Cleanup complete; finished."
}

intercept_break() {
    echo -e "\nBreak detected; cleaning up and exiting gracefully..."
    cleanup
    exit 1
}
trap intercept_break SIGINT # Set the trap for SIGINT (CTRL-C)


# Loop through all subdirectories in the lectures folder
#
# Note: The folders have spaces in the path, so we need to properly escape strings. ffmpeg has some issues with 
# subprocesses created by e.g.: find "${SOURCE_PATH}" -mindepth 1 -type d | sort | while IFS= read -r path; do
# so we use mapfile to create an array in a regular for-loop, without creating subprocesses
#
# Explanation:
#   -print0:      outputs file paths as null-delimited strings, to handle spaces and special characters safely
#   tr '\0' '\n': converts null-delimited strings to newline-delimited ones, allowing sort to process them
#   sort -V:      sorts the file names in version-aware order, ensuring e.g. 10 comes after 9 (important for filenames)
#   mapfile -t:   reads the newline-delimited outpu tinto an array, with each path as a separate element
#
INDEX_FILE="index.txt"
id=1
mapfile -t folders < <(find "${SOURCE_PATH}" -mindepth 1 -type d -print0 | tr '\0' '\n' | sort -V)
for path in "${folders[@]}"; do
    base_path=$(basename "${path}")
    echo "+ Processing subdirectory: ${base_path}"

    # -- Loop through each video
    videos_found=0
    mapfile -t files < <(find "${path}" -maxdepth 1 -name "*.${VIDEO_FORMAT}" -print0 | tr '\0' '\n' | sort -V )
    for source_video_path in "${files[@]}"; do
        videos_found=1
        # normalize original video
        source_video=$(basename "${source_video_path}" .${VIDEO_FORMAT})
        normalized_source_video="segment-normalized.${VIDEO_FORMAT}"
        echo "+--- Processing video ${id}/${total_files}:  [${source_video_path}] "
        ffmpeg -y ${HW_ACCEL} -i "${source_video_path}" -c:v ${ENCODER} -preset ${PROFILE_PRESET} ${CRF} -vf "${VF_SCALE}=${ASPECT_RATIO},fps=${FRAMERATE}" -c:a copy -b:a 128k -maxrate ${BITRATE} -bufsize ${BITRATE}  ${DEBUG} "${TEMP_DIR}/${normalized_source_video}"

        # Create a 5s cover page (with silent audio)
        title1=$(sed 's/__/ - /g' <<< "${base_path}" | sed 's/_/ /g' | fold -sw ${MAX_LINE_LEN_L1})
        title2=$(sed 's/_/ /g' <<< "${source_video}" | fold -sw ${MAX_LINE_LEN_L2})
        cover_path="cover.${VIDEO_FORMAT}"
        ffmpeg -y \
                -fflags +genpts \
                -f lavfi -i "color=c=${BG_COLOR}:s=1280x720:d=${INTRO_DURATION}" \
                -f lavfi -i "anullsrc=channel_layout=stereo:sample_rate=44100" \
                -vf "drawtext=fontfile='${FONT_FILE}':text='${title1}':x=100:y=200:fontsize=${FONT_SIZE_L1}:fontcolor=${FONT_COLOR_L1},drawtext=fontfile='${FONT_FILE}':text='${title2}':x=100:y=300:fontsize=${FONT_SIZE_L2}:fontcolor=${FONT_COLOR_L2},scale=${ASPECT_RATIO},setsar=1,fps=${FRAMERATE},format=yuv420p" \
                -c:v ${ENCODER} -pix_fmt yuv420p -c:a aac -shortest -avoid_negative_ts make_zero ${DEBUG} "${TEMP_DIR}/${cover_path}"

        # Concatenate cover page + video segment
        concat_list="${TEMP_DIR}/concat_list.txt"
        concat_segment="${TEMP_DIR}/segment-${id}.${VIDEO_FORMAT}"
        ((id++))
        > "${concat_list}"  # zero file
        echo "file '${cover_path}'" >> "${concat_list}"
        echo "file '${normalized_source_video}'" >> "${concat_list}"
        ffmpeg -y -f concat -safe 0 -i "$concat_list" -c:v copy -c:a copy ${DEBUG} "${concat_segment}"

        # add the concatenated segment for final merge, and cleanup temporary segment files
        echo "file '${concat_segment}'" >> "${INDEX_FILE}"
        rm "${TEMP_DIR}/${normalized_source_video}"
        rm "${TEMP_DIR}/${cover_path}"
        rm "${concat_list}"
    done
    if [[ "${videos_found}" -eq "1" ]]; then
        output_file=$(echo "${base_path}.${VIDEO_FORMAT}" | sed 's/__/ - /g' | tr '_' ' ')
        echo "+--- Writing chapter file: ${output}"
        ffmpeg -y -f concat -safe 0 -i "${INDEX_FILE}" -c:v copy -c:a copy ${DEBUG} "${OUTPUT_PATH}/${output_file}"
        rm "${INDEX_FILE}"
        rm ${TEMP_DIR}/segment*.${VIDEO_FORMAT}
    fi
done

cleanup
