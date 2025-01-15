# VidCat: Video Concatenation Tool

VidCat is a Bash script designed to streamline the process of concatenating multiple small video files into a single longer video, using `ffmpeg`.

It was created mostly to address my desire to watch [OMSCS lectures](https://omscs.gatech.edu/) on the go. I found distracting to watch dozens of 2-3min short episodes, plus the issues most proprietary mobile apps have in remembering your watch speed preferences, or the position you were when you last watched, or when watching offline on mobile. This is particularly important when watching content on my commute, as I won't have connectivity most of the time (looking at you, NYC MTA).

VidCat supports features like:
- Automatic cover page generation.
- Nvidia GPU acceleration for faster encoding (if available).
- Customizable encoding parameters (e.g., frame rate, video format, and resolution).

VidCat was tested on Ubuntu 22.04. The cover page is generated automaticaly *based on the sub-directories and filenames*, so you need to organize your input files in logical order. For example:

```text
./lectures:
    |
    +-- 1. introduction/
    |       |
    |       +-- 1.1 this is the first file.mp4
    |       +-- 1.2 this is the second file.mp4
    |       +-- 1.3 this is the third file.mp4
    |       +-- 1.4 this is the fourth file.mp4
    |       +-- 1.5 this is the fifth file.mp4
    |
    +-- 2. advanced topics/
            |
            +-- 2.1 this is advanced topic 1.mp4
            +-- 2.2 this is advanced topic 2.mp4
```
VidCat will create two files: `1. introduction.mp4`, and `2. advanced topics.mp4`.

> *Note for OMSCS students*: I've successfuly used this with the downloadable lectures for CS-7646 (ML4T) and CS-6200 (GIOS), but YMMV. GIOS' lectures are already nicely organized in subfolders for each chapter (P1L1, P1L2, P2L4, etc), so it works beautifully out of the box. ML4T lectures are all in a single folder (with some random subfolders sprinkled through it), so you need to move files around and create subdirectories for each chapter. Other classes may require similar tweaking.
 
In between each video segment VidCat will add a cover page with the chapter and segment title. For example: 

![cover page](images/screenshot-coverpage.png | width=200)

All fonts, font sizes and colors are easily customizable; see script for details.

## Features
- **Automatic Cover Pages**: adds a customizable introduction page at the beginning of each concatenated episode.
- **Video Normalization**: ensures all videos match a consistent resolution, frame rate, and format. This adds one-time processing time, but ensures the output video will play on all devices.
- **(optional) GPU Acceleration**: uses Nvidia's nvenc codec for faster video encoding.
- **(optional) in-memory virtual disk for temporary files**: to avoid 

## Usage
Run VidCat with the following command:
```bash
./vidcat <input_directory> [(optional) output_directory]
```

You should see something like this while processing your videos:

![processing](images/screenshot-processing.png | width=200)

Depending on the size of your original videos, this may take quite a bit to finish (e.g. OMSCS GIOS / CS-6200 has 6GB across 576 individual video files; it took 71 minutes to finish using CPU, and 35 minutes using GPU acceleration).

### Output
- A series for video files for each chapter (`chapter 1.mp4`, `chapter 2.mp4`, ...) with normalized resolution, frame rate, and an introduction cover page for each episode. Each *chapter* is defined as a subdirectory inside `<input directory>`. The script does some minimal sanitization of filenames (e.g. underscores are converted to spaces, and double underscores are replaced by " - "). Spaces and special characters are allowed.

## Customization
You can customize the script by editing its variables directly. Some notable examples:

- **`FRAMERATE`**: Default frame rate (`30000/1001`). Should match the input videos being concatenated
- **`VIDEO_FORMAT`**: default video format. This was only tested with mp4, but should (probably?) work with other formats
- **`INTRO_DURATION`**: Duration of the introductory cover page.
- **`FONT_FILE`**: Specify a custom ttf font for cover page text (also size, colors, and max length)
- **`ASPECT_RATIO`** and **`BITRATE`**: Output video resolution/bitrate. Use the highest resolution of videos segments inside each chapter / subdirectory.
- **`NVIDIA_GPU`**: Enable/disable Nvidia GPU. Default: disabled. See [Troubleshooting](#troubleshooting) if you have any issues.
- **`USE_VIRTUAL_DISK`**: Use in-memory virtual disk for temporary files. Slightly faster, and avoids SSD wear, but requires `sudo` and enough RAM.


## Prerequisites
* [**FFmpeg**](https://www.ffmpeg.org/). Mine is a rather old 4.4.2, so anything after that should work.
* **Bash shell**. VidCat relies on Bash's builtin [radarray/mapfile](https://ss64.com/bash/mapfile.html), which is [not available](https://www.reddit.com/r/zsh/comments/tt6gm8/why_doesnt_zsh_have_an_equivalent_of_bashs/) in other shells. You'll need to modify if running on a non-bash environment.
* (Optional) **GPU Acceleration**. If you have an NVIDIA card and want to use GPU acceleration (2-3x speedup), ensure your CUDA libraries and drivers are properly installed, and FFmpeg was compiled with GPU acceleration.

* (Optional) **Custom font** for the cover page. I use [WarGames font](https://www.1001fonts.com/wargames-font.html) (see above), becase, why not :)
* (Optional) **In-memory virtual disk**. Create a tmpfs virtual disk to store temporary files. Besides slightly faster speed, main benefit is avoiding writing several GBs to disk. Disabled by default, as it requires `sudo` (to mount/dismount tmpfs).

## Installation
```bash
# clone the repository and navigate to the directory:
git clone https://github.com/yourusername/vidcat.git
cd vidcat

# make the script executable:
chmod +x vidcat

# download the original lecture videos, and run VidCat to concatenate into chatpers
vidcat /path/to/lecture/videos
```

## Troubleshooting
1. **This takes too long to run!**:
    Yes, indeed. VidCat re-encodes the videos from scratch, so it takes quite a bit of time. The advantage is that the resulting file will be more robust, and likely to play without any PUlitches in most devices.
    
    The reason to re-encode files is that lectures are sometimes encoded with different resolutions/bitrates/codecs, so purely concatenating videos results in problems when fast-forwarding the video, or sometimes making it totally unplayable.
  
    Having said that, if you *really* want to want to skip re-encoding the original videos, look for `# normalize original video` section of the script, and change ffmpeg to use `-c:v copy` instead of the default H264 encoder used.

2. **I don't know which resolution to use**
   Investigate your source files with `ffprobe -i input.mp4 -show_streams -pretty`. Note that different files may have different resolutions; use `utils/find_maxres.sh` on a directory to find the maximum resolution used. `1280:720` is usually a safe bet, or `640:360` is you need to minimize storage space (e.g. mobile devices).

3. **Output files are much bigger than the original files**:
   There's a good chance that the resolution of original videos is much lower than what VidCat is using. Investigate the resolution using `ffprobe -i input.mp4 -show_streams -pretty` and adjust `ASPECT_RATIO` and `BITRATE` parameters accordingly

4. **Nothing happens. The script runs, but no files are generated**:
   FFmpeg output is suppressed by default. Set `FFMPEG_VERBOSE=1` and check for warning/errors on FFmpeg's output.

5. **CUDA_ERROR_COMPAT_NOT_SUPPORTED_ON_DEVICE: forward compatibility was attempted on non supported HW**:
   - Ensure your FFmpeg is compiled with NVIDIA NVENC support.
   - Verify GPU functionality with:
   ```bash
    # check CUDA version (e.g. 2.6) and driver
    nvidia-smi

    # should show up several lines for nvenc
    ffmpeg -encoders -loglevel quiet | grep NVENC
    
    # try to encode a test file. Provide any mp4 input
    ffmpeg -i in.mp4 -c:v h264_nvenc -preset fast -b:v 5M out.mp4
   ```


## License
This project is licensed under the MIT License.

## Contributions
Contributions are welcome! Feel free to fork the repository, make improvements, and submit a pull request.


