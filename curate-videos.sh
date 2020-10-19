#!/bin/bash

### INFORMATION ######################################################################################################

# Script Name    :  curate-videos.sh
# Orginal Author :  Andy Sibthorp

# Description
# This script has 2 modes.
#
# Command Line Mode
#   This is the default mode of operation.
#   See the usage instructions to see what can be done.  (look in the fDisplayUsage function)
#
# Auto Mode
#	This script looks for mkv and mp4 files in the directory specifed in the settings section.
#	Any file names that contain a Series / Episode number string will be treated as Shows, all other files will be treated as Films.
#	Films will be moved to the directory specified in the settings section.
#	Shows will be moved to the directory specified in the settings section.
#	Any mkv and mp4 files that are too small will be ignored (Size can be specified).
#	Files bigger than a specified size will have their subtitle streams removed using mkvmerge before they are moved into the right place.
#	All output is logged to a file as well as display on screen.


# Version : 2.6
# Date    : 18/10/2020
# Author  : Andy Sibthorp
# Release Notes:
#   Added function to exclude files using key strings. Key Strings must be saved in a file which is specified using the -E switch

# Version : 2.5
# Date    : 26/06/2020
# Author  : Andy Sibthorp
# Release Notes:
#   Bug fixes for the manual mode not passing the parameters correcly.

# Version : 2.4
# Date    : 12/06/2020
# Author  : Andy Sibthorp
# Release Notes:
#   Changed match filter switch from -m to -f
#   Added -m option to allow for manual selection of track that are included in the mkvmerge processing. This option presents a menu so requires user interaction. Works with both file and dir, auto and commandline modes.

# Version : 2.3
# Date    : 08/06/2020
# Author  : Andy Sibthorp
# Release Notes:
#   Changed the way the script handles isrunning detection. It now looks for the process using pgrep rather than a file created by the script. It also logs to the systemd journal when another instance of the script is detected.

# Version : 2.2
# Date    : 06/06/2020
# Author  : Andy Sibthorp
# Release Notes:
#   Added ability to skip files with the word "sample" in the filename. The default behaviour is to skip those files but the -S option will include those files instead. Can be set in the user settings for auto mode.
#   Fixed cosmetic issues with displaying source file and source path on screen / in logs.
#   Fixed auto mode setting that allows for a single target directory to be used instead of the 2 directory - Films and Shows. (Turns out I didn't finish implementing it).

# Version : 2.1 (Gray's Birthday Extended Edition)
# Date    : 31/05/2020
# Author  : Andy Sibthorp
# Release Notes:
#   Added option to retain english and undetermined audio and subtitle tracks but remove all other languages (Option is -e).

# Version : 2.0 (Gray's Birthday Edition)
# Date    : 25/05/2020
# Author  : Andy Sibthorp
# Release Notes:
#   Significant features added. (As requested by Graham Prior)
#		Command line options now avaible for those special one off runs.
#	General changes
#		Removed the echolog function and replaced it with a solution that catches output from anyting the script does that outputs a message. ( exec > >(tee -a "$strLogFileNameAndPath") 2>&1 )
#		When mkvmerge removes the subtitles (SRT) the original file gets .WithSRT added to the filename.
#		Changed some variable names to be more generic (e.g. completeddownloads are now just sources)
#		Added ERROR and WARNING messages with a shit load of conditional checks.
#		Pretty much a total re-write, actually.

# Version : 1.4
# Date    : 23/05/2020
# Author  : Andy Sibthorp
# Release Notes:
#   Added fCheckPaths function to report if any of the paths defined in the user settings variables are invalid.
#   If any paths are invalid a log file will be created at PWD titled curate-videos-ERRORS.log containing the list of invalid paths.

# Version : 1.3
# Date    : 14/05/2020
# Author  : Andy Sibthorp
# Release Notes:
#	Now creates log files.
#	Location for log files is be specified in the settings section.
#	Number of log files to keep is be specified in the settings section.

# Version : 1.2
# Date    : 12/05/2020
# Author  : Andy Sibthorp
# Release Notes:
#	Removed the step that checked if there are any subtitles in the file because mkvinfo is not good at this. This means ALL files above the specifed size will be mkvmerged even if they don't have subtitles in them.
#	Now supports files not in a sub folder. Previously it was assumed all downloads what have their own subfolder but this is not 100% true.
#	Moved delete phase to the end of the script.
#	Cleaned up the messages

# Version : 1.1
# Date    : 11/05/2020
# Author  : Andy Sibthorp
# Release Notes-
#	Added function to detect if the script is already running. (User setting strScriptIsRunningMarkerFileAndPath specifies the file and path)
#	Loops multiple times until all files are gone in case more files are added after the script started.
#	Limited the number of loops (User setting intLoopLimit allows you to change this)

# Version : 1.0
# Date    : 11/05/2020
# Author  : Andy Sibthorp
# Release Notes
#	First production release



### Static Definitions ################################################################################################
intVerion="2.3"

IFS=""

###### User Settings for Auto Mode - START #######

	ApplyAutoModeSettings() {

		# Two Target folders to split Films and Shows. If strTargetDir is set to none these 2 Target dir settings are ignored.
		strTargetDirFilms="/mnt/pi-drive-01/Films"
		strTargetDirShows="/mnt/pi-drive-01/TV-Shows"

		# Target directory path to move the source files into. Set to the word none if you want to use the Films / Shows settings above.
		strTargetDir=none

		# Directory path for mkvmerge to output files to when it is removing subtitles.
		strTargetDirMKVMergeTemp="/mnt/pi-drive-01/torrents/mkvmergetemp"

		# Directory path where the source files are located (Can be the top of a structure to be recursed through).
		strSourcePath="/mnt/pi-drive-01/torrents/complete"

		# Skip files with the word "sample" in the filename
		strSkipSampleFiles=true

		# The minimum size of file to process. Files smaller than this will be ignored.
		intMinFileSizeToIgnoreInMB=15

		# The minimum size of file to strip subtitles from. Only files bigger than this value will have their subtitles removed.
		intMinFileSizeToTriggerSubtitleRemovalInGB=2

		# Directory path for the logm files
		strLogFilesDir="/mnt/pi-drive-01/torrents/curate-videos-logs"
		
		# List of names to exclude from being processed by mkvmerge. They will still be moved into the correct folder.
		strExcludesListFileNameAndPath="/mnt/pi-drive-01/torrents/curate-videos-exclude-strings.txt"

		# Number of log files to keep
		intNumberOfLogFilesToKeep=1800

		# file or dir
		strFileSelectionMode=dir

		# true or false
		strOverWriteTarget=true

		# true or false
		strDeleteSource=true

		# true or false or limited
		strRecurseSourceDir=true

		# Max number of sub directories to recurse into (1 = current only). - Only valid if strRecurseSourceDir=false
		strRecurseLimiterMaxDepth=1

		# Keep English Audio and Subtitles
		strKeepEnglishAudioAndSubtitles=true

		# The number of times to loop.
		intLoopLimit=5
		
		# No excludes by default in commandline mode.
		strCheckForExcludes=true
	}

###### User Settings for Auto Mode - END #######


###### User Settings for Command Line Mode - START #######

	ApplyCmdLineDefaultSettings() {
		### Set Commandline Mode Defaults

		# Keep English Audio and Subtitles
		strKeepEnglishAudioAndSubtitles=false

		# true or false
		strOverWriteTarget=false

		# true or false
		strDeleteSource=false

		# true or false
		strRecurseSourceDir=false

		# File or Directory path (Unless you always want to target the same file everytime I suggest you always make the default source a directory
		strSourcePath="$PWD"

		# Directory Path
		strTargetDirMKVMergeTemp="$PWD/mkvmergetemp"

		# Directory path
		strTargetDir="$PWD"

		# 1 = current only. Effectively no recurse.
		strRecurseLimiterMaxDepth=1

		# Filter type all / shows / films (See Usage info)
		strFilterMatchType=all

		# The minimum size of file to process. Files smaller than this will be ignored.
		intMinFileSizeToIgnoreInMB=0

		# The minimum size of file to strip subtitles from. Only files bigger than this value will have their subtitles removed.
		intMinFileSizeToTriggerSubtitleRemovalInGB=0
		
		# No excludes by default in commandline mode.
		strCheckForExcludes=false
	}

###### User Settings for Command Line Mode - END #######


###### Common System - START #######

	#  **** Avoid changing these settings unless you know what you are doing ****

	ApplyCommonSystemSettings() {

		intOneMegaByteInBytes="1048576"
		intOneGigaByteInBytes="1073741824"
		intFileSizeToIgnore=$(expr $intOneMegaByteInBytes \* $intMinFileSizeToIgnoreInMB)
		intFileSizeToTriggerSubtitleRemoval=$(expr $intOneGigaByteInBytes \* $intMinFileSizeToTriggerSubtitleRemovalInGB)
		strDoTheloop=true
	}

###### Common System Settings - END #######



###### Core System Defaults - START #######

	#  **** Avoid changing these settings unless you know what you are doing ****

	# Prevent the script for actually doing anything by setting this to true
	strWhatIfMode=false

	# Make the commandline mode the default.
	strExecutionMode=commandline

	# Default to dir mode because you can't really default to file mode without a file name to work with.
	strFileSelectionMode=dir

	# Skip files with the word "sample" in the filename
	strSkipSampleFiles=true

	# Let the user manually select which tracks to include in the mkvmerge output
	strManualTrackSelection=false

	# Colour Codes
	RESETCOLOUR='\033[0m'
	RED='\033[0;31m'
	GREEN='\033[0;32m'
	ORANGE='\033[0;33m'
	BLUE='\033[0;34m'
	PURPLE='\033[0;35m'
	CYAN='\033[0;36m'
	LIGHTGRAY='\033[0;37m'
	DARKGRAY='\033[1;30m'
	LIGHTRED='\033[1;31m'
	LIGHTGREEN='\033[1;32m'
	YELLOW='\033[1;33m'
	LIGHTBLUE='\033[1;34m'
	LIGHTPURPLE='\033[1;35m'
	LIGHTCYAN='\033[1;36m'
	WHITE='\033[1;37m'

###### Core System Defaults Settings - END #######




### FUNCTIONS ####################################################################################

function fDisplayUsage() {
	echo ""
	echo "This script will organise a set of mkv and mp4 files into the desired location with an option to remove any subtitles from those files in the process using mkvmerge. The conditions for each of those actions can be set by the user."
	echo ""
	echo "There are 2 modes of operation:"
	echo "'Command Line' mode uses the options described below. This is the default mode of operation."
	echo "'Auto' mode uses the settings defined inside the script. Those settings located after the comments section. Use the -a option to enable Auto mode. In Auto mode the script will output log files and loop several times."
	echo ""
	echo "Usage:"
	echo "  curate-videos [OPTIONS]... {-s [DIR or FILE (Default is current dir)]...} {-t [DIR (Default is current dir)]...}"
	echo ""
	echo "   -h   Show this help information"
	echo "   -w   What If mode - Runs without actually doing anything."
	echo "   -a   Auto Mode - The script will use the user settings inside the script and iIngores all other command line options, except for -m -w options"
	echo "   -e   Keep english and undetermined audio and subtitle tracks but remove all other languages"
	echo "   -S   Include files with sample in the filename - Default is to skip those files."
	echo "   -o   Overwrite target file(s) -- Default is NOT overwrite"
	echo "   -x   Delete source Directory / file(s) -- Default is NOT delete"
	echo "   -r   Recurse Source directory -- Find files within source the specified directory and its sub-directories -- Default is NOT recurse"
	echo "   -m   Manually select the tracks to include in the mkvmerge output -- Overrides -e option"
	echo ""
	echo "   -d <number>           Depth - Limit recurse to the number of directories -- 1 = do not recurse"
	echo "   -E [Path/Filename]    A file of strings used to exclude files from being processesd by mkvmerge. The files will still be moved."
	echo "   -s [FILE or DIR]      Source directory or File -- Default is current directory"
	echo "   -t [DIR]              Target directory -- Default is current directory"
	echo "   -f <all/shows/films>  Match using the built in filters -- See filter types below"
	echo "   -T [DIR]              Temp directory for mkvmerge -- Default is current directory"
	echo ""
	echo "Filters: This script contains the following 3 built in filters."
	echo "   all      No filters. Select all mkv and mp4 files in the specified source directory (This is the Default in command line mode)"
	echo "   shows    Filter for mkv and mp4 files with filenames contain the season / episode pattern. e.g. S01E06 and similar"
	echo "   films    Filter for mkv and mp4 files with filenames the does NOT contain the season / episode pattern. e.g. S01E06 and similar"
	echo ""
	echo "NOTE: mkvmerge required for the subtitle removal function to work."
	echo "      -m requires user input. It will work with auto mode but so is not suitable for use with a cron job."
	echo ""
	echo "WARNING: This script will delete entire directory structures without prompting if instructed to do so. Be careful!"
	echo ""
	exit 2
}

function fCheckPaths()  {
	strCurrentIFS=$IFS
	IFS=$'\n'
	
	arrBadPaths=()

	if [ ! -d "$strTargetDirFilms" ]
	then
		arrBadPaths+=("User setting: strTargetDirFilms = $strTargetDirFilms")
	fi

	if [ ! -d "$strTargetDirShows" ]
	then
		arrBadPaths+=("User setting: strTargetDirShows = $strTargetDirShows")
	fi

	if [ ! -d "$strTargetDirMKVMergeTemp" ]
	then
		arrBadPaths+=("User setting: strTargetDirMKVMergeTemp = $strTargetDirMKVMergeTemp")
	fi

	if [ ! -d "$strSourcePath" ]
	then
		arrBadPaths+=("User setting: strSourcePath = $strSourcePath")
	fi

	if [ ! -d "$strLogFilesDir" ]
	then
		arrBadPaths+=("User setting: strLogFilesDir = $strLogFilesDir")
	fi

	if [ ! -f "$strExcludesListFileNameAndPath" ]
	then
		arrBadPaths+=("User setting: strExcludesListFileNameAndPath = $strExcludesListFileNameAndPath")
	fi

	if [ "$strTargetDirMKVMergeTemp" = "$strTargetDirShows" ] || [ "$strTargetDirMKVMergeTemp" = "$strTargetDirFilms" ] || [ "$strTargetDirMKVMergeTemp" = "$strSourcePath" ]
	then
		echo "The MKVmerge temp directory cannot be the same as the source or target directories"
	fi

	# Display the list of bad paths.
	if [ ${#arrBadPaths[@]} -gt 0 ]
	then
		strLogFileNameAndPath="$HOME/curate-videos-ERRORS.log"
		touch "$strLogFileNameAndPath"
		if [ $? -eq 0 ]
		then
			exec > >(tee -a "$strLogFileNameAndPath") 2>&1
		fi
		echo ""
		echo "ERROR-01: Invalid Paths defined in the user settings."
		echo ""
		for strBadPath in ${arrBadPaths[@]}
		do
			echo "$strBadPath"
		done
		echo ""
		echo "Above errors also logged to $strLogFileNameAndPath"
		echo ""
		exit
	fi

	IFS=$strCurrentIFS
}


function fHandleLogs() {
	strCurrentIFS=$IFS

	# Make sure the logs dir is writable.
	if [ ! -w "$strLogFilesDir" ]
	then
		echo "ERROR-02: Cannot write to the logs directory $strLogFilesDir"
		exit 1
	fi
	
	# Create new log file
	strLogFileNameAndPath="$strLogFilesDir/curate-videos_$(date +"%y%m%d_%H%M%S".log)"
	while [ -f "$strLogFileNameAndPath" ]
	do
		strLogFileNameAndPath="$strLogFilesDir/curate-videos_$(date +"%y%m%d_%H%M%S".log)"
	done
	touch "$strLogFileNameAndPath"
	if [ $? -gt 0 ]
	then
		echo "ERROR-03: Cannot create log file!"
		exit 1
	fi

	# Delete oldest log file if there now more log files than specifed in intNumberOfLogFilesToKeep
	IFS=$'\n'
	arrAllLogsFiles=($(ls "$strLogFilesDir"/curate-videos_*.log | sort))

	if [ ${#arrAllLogsFiles[@]} -gt $intNumberOfLogFilesToKeep ]
	then
		strOldestLogFile=(${arrAllLogsFiles[0]})
		echo "Deleting old log file: $strOldestLogFile"
		rm -f "$strOldestLogFile"
		if [ $? -gt 0 ]
		then
			echo "WARNING-01: rm -f $strOldestLogFile"
		fi
	fi

	IFS=$strCurrentIFS
}

function fSelectListOfTracksToInclude() {
	keepIFS=$IFS

	arrSelectedTracks=()
	arrSelectedTracksVideos=()
	arrSelectedTracksAudio=()
	arrSelectedTracksSubtitle=()
	strTrackSelectionFinished=false
	strInvalidSelection=""
	strMenuChoice=""
	strSkipThisFile=false
	strRemoveAllSubtitles=false
	strMissingTrackSelections=false

	echo ""
	local strSourceFileToRead="$@"
	IFS=$'\n'
	arrListOfTracks=($(mkvmerge -i "$strSourceFileToRead" | grep "Track ID"))

	while [ $strTrackSelectionFinished = false ]
	do
		strMenuChoiceAlreadyUsed=false

		echo -e "\n$LIGHTGREEN  --- Track Selection Menu ---$RESETCOLOUR\n"

		for strTrack in ${arrListOfTracks[@]}
		do :
			echo "  $strTrack"
		done

		echo ""
		if [ ${#arrSelectedTracks[@]} -gt 0 ]
		then
			echo "  F = Finished Selecting"
			strMenuOptions="F/C/S/D/A"
		else			
			strMenuOptions="C/S/D/A"
		fi
		echo "  C = Clear selection list"
		echo "  E = Exclude ALL subtitles"
		echo "  D = Don't process this file"
		echo "  A = Abort Script"
		echo ""
		echo -e "$LIGHTGREEN  Selected Track ID's:$WHITE ${arrSelectedTracks[@]} $RESETCOLOUR"
		echo -e "$strInvalidSelection"
		if [ ! "$strMissingTrackSelections" = "false" ]
		then
			echo -e "$strMissingTrackSelections"
		fi

		if [ ${#arrSelectedTracks[@]} -lt ${#arrListOfTracks[@]} ]
		then
			echo -e -n "$WHITE  Enter a track number or Select : $RESETCOLOUR"
		else
			echo -e -n "$YELLOW  No more tracks available. This is effectively a full copy. Select $strMenuOptions? $RESETCOLOUR"
		fi

		read -r strMenuChoice

		# User didn't provide any input and just hit return
		if [ $strMenuChoice = "" 2> /dev/null ] || [ ! $strMenuChoice ]
		then
			continue
		fi

		# User selected option C
		if [ ${strMenuChoice,,} = c ]
		then
			arrSelectedTracks=()
			arrSelectedTracksVideos=()
			arrSelectedTracksAudio=()
			arrSelectedTracksSubtitle=()
			strInvalidSelection=""
			strRemoveAllSubtitles=false
			strMissingTrackSelections=false
			continue
		fi

		# User select option F - Only valid if tracks have been selected.
		if [ ${strMenuChoice,,} = f ] && [ ${#arrSelectedTracks[@]} -gt 0 ]
		then

			if [ ${#arrSelectedTracksVideos[@]} -gt 0 ]
			then
				strParamVideoTracks="$(echo ${arrSelectedTracksVideos[@]} | tr " " ",")"
			else
				strMissingTrackSelections+="\n$YELLOW  No video tracks selected$RESETCOLOUR"
			fi

			if [ ${#arrSelectedTracksAudio[@]} -gt 0 ]
			then
				strParamAudioTracks="$(echo ${arrSelectedTracksAudio[@]} | tr " " ",")"
			else
				strMissingTrackSelections+="\n$YELLOW  No audio tracks selected$RESETCOLOUR"
			fi

			if [ ${#arrSelectedTracksSubtitle[@]} -gt 0 ] && [ $strRemoveAllSubtitles = false ]
			then
				strParamSubtitleTracks="$(echo ${arrSelectedTracksSubtitle[@]} | tr " " ",")"
			elif [ $strRemoveAllSubtitles = true ]
			then
				strParamSubtitleTracks="--no-subtitles"
			else
				strMissingTrackSelections+="\n$YELLOW  No subtitle tracks selected$RESETCOLOUR"
			fi

			echo ""

			if [ "$strMissingTrackSelections" = "false" ]
			then
				strTrackSelectionFinished=true

				echo -e "$WHITE"
				echo "The following tracks will be included in the mkvmerge process"
				echo ""
				for intTrackNum in ${arrSelectedTracks[@]}
				do :
					if [ $intTrackNum = "[Exclude All Subtitles]" ]
					then
						echo "  $intTrackNum"
					else
						echo "  ${arrListOfTracks[$intTrackNum]}"
					fi
				done
				echo -e "$RESETCOLOUR"
				IFS=$keepIFS
				return
			else
				continue
			fi
		fi

		# Quit the menu and just use the --no-subtitles option for mkvmerge
		if [ ${strMenuChoice,,} = e ]
		then
			strRemoveAllSubtitles=true
			arrSelectedTracks+=("[Exclude All Subtitles]")
			strMissingTrackSelections=false
			continue
		fi

		# Skip this file.
		if [ ${strMenuChoice,,} = d ]
		then
			strSkipThisFile=true

			IFS=$keepIFS
			return
		fi

		# Abort the script.
		if [ ${strMenuChoice,,} = a ]
		then
			echo -e "\n$LIGHTRED  Aborted!\n"
			exit 1
		fi

		# Add track selection the required list.
		if [ $strMenuChoice -lt ${#arrListOfTracks[@]} 2> /dev/null ]
		then
			for strSelectedTrack in ${arrSelectedTracks[@]}
			do :
				if [ "$strMenuChoice" = "$strSelectedTrack" ]
				then
					strMenuChoiceAlreadyUsed=true
				fi
			done
		
			if [ $strMenuChoiceAlreadyUsed = false ]
			then
				if [ $(echo ${arrListOfTracks[$strMenuChoice]} | grep "video" -c -i) -gt 0 ]
				then
					arrSelectedTracksVideos+=("$strMenuChoice")
				fi
				if [ $(echo ${arrListOfTracks[$strMenuChoice]} | grep "audio" -c -i) -gt 0 ]
				then
					arrSelectedTracksAudio+=("$strMenuChoice")
				fi
				if [ $(echo ${arrListOfTracks[$strMenuChoice]} | grep "subtitle" -c -i) -gt 0 ]
				then
					arrSelectedTracksSubtitle+=("$strMenuChoice")
				fi
				arrSelectedTracks+=("$strMenuChoice")
				strInvalidSelection=""
			else
				strInvalidSelection="\n$YELLOW  Invalid input. $WHITE\"$strMenuChoice\" has already been selected $RESETCOLOUR\n"
			fi
			strMissingTrackSelections=false
			continue
		fi

		strInvalidSelection="\n$YELLOW  Invalid input $WHITE\"$strMenuChoice\" $RESETCOLOUR\n"
		IFS=$keepIFS
	done

	echo "ERROR-21: You managed to provide input that screwed the menu. Well done."
	exit 1
}


function fProcessFilesInDir() {
	# Diplay the settings and how many files will be processed.
	echo ""
	echo "==============================================================================="
	echo ""
	echo "Source directory  : $strSourcePath"
	echo "Filtering for     : $strFilterMatchType   [.mkv and .mp4 files only]"
	echo "Skip Sample Files : $strSkipSampleFiles"
	echo "Overwrite Targets : $strOverWriteTarget"
	echo "Delete Sources    : $strDeleteSource"
	echo "Keep English Subs : $strKeepEnglishAudioAndSubtitles"

	if [ $strRecurseSourceDir = limited ]
	then
		echo "Recurse Source Dir: $strRecurseSourceDir"
		echo "Recurese Max Depth: $strRecurseLimiterMaxDepth"
	else
		echo "Recurse Source Dir: $strRecurseSourceDir"
	fi

	
	# Init Vars
	IFS=$'\n'
	arrDirsToDelete=()
	arrFilesToDelete=()

	# Get the files list
	IFS=$'\n'
	if [ $strRecurseSourceDir = true ]
	then
		case ${strFilterMatchType,,} in
			shows )
				arrFilesToProcess=($(find "$strSourcePath" -type f -iname '*.mkv' -o -iname '*.mp4' | grep -P '([Ss]?)(\d{1,2})([xXeE\-])(\d{1,2})'))
				;;
			films )
				arrFilesToProcess=($(find "$strSourcePath" -type f -iname '*.mkv' -o -iname '*.mp4' | grep -v -P '([Ss]?)(\d{1,2})([xXeE\-])(\d{1,2})'))
				;;
			all )
				arrFilesToProcess=($(find "$strSourcePath" -type f -iname '*.mkv' -o -iname '*.mp4'))
				;;
		esac
		
	elif [ $strRecurseSourceDir = limited ] || [ $strRecurseSourceDir = false ]
	then
	
		case ${strFilterMatchType,,} in
			shows )
				arrFilesToProcess=($(find "$strSourcePath" -maxdepth $strRecurseLimiterMaxDepth -type f -iname '*.mkv' -o -iname '*.mp4' | grep -P '([Ss]?)(\d{1,2})([xXeE\-])(\d{1,2})'))
				;;
			films )
				arrFilesToProcess=($(find "$strSourcePath" -maxdepth $strRecurseLimiterMaxDepth -type f -iname '*.mkv' -o -iname '*.mp4' | grep -v -P '([Ss]?)(\d{1,2})([xXeE\-])(\d{1,2})'))
				;;
			all )
				arrFilesToProcess=($(find "$strSourcePath" -maxdepth $strRecurseLimiterMaxDepth -type f -iname '*.mkv' -o -iname '*.mp4'))
				;;
		esac

	else

		echo "Bad Recurse Option. Did you edit the script?"
		exit 1
	fi


	# If files are found to process then begin
	if [ ${#arrFilesToProcess[@]} -gt 0 ]
	then
		# Diplay count of found files.
		echo ""
		echo "Files found to Process: ${#arrFilesToProcess[@]}"

		# Main loop starts here.
		for strSourceFile in "${arrFilesToProcess[@]}"
		do :
			# Display significant event seperator
			echo ""
			echo "-------------------------------------------------------------------------------"
			echo ""
			
			# Reset the strActionFileMoveOnly status to false
			strActionFileMoveOnly=false

			# Reset strSourceFileRenamed to default value.
			strSourceFileRenamed=false
			
			# Split the file name from from the dir path in strSourceFile
			strSourceFileName=$(basename "$strSourceFile")
			
			# Setup the destination paths and include the file name.
			IFS=''
			strTargetDirAndFileName="$strTargetDir/$strSourceFileName"
			
			# Get full directory path of source file without filename.
			IFS=''
			strSourceFullDir="$(dirname "$strSourceFile")"

			# Because files could be stored in a sub folder of sub folders of sub folder . . . we need to identify the top sub folder to delete the structure.
			# Check if the file is inside a sub directory. This decides what gets deleted at the end (A file or a directory structure)
			if [ "$strSourceFullDir" = "$strSourcePath" ]
			then
				echo "Source File: .../$strSourceFileName"
				strInSubDir=false
			else
				IFS='/'
				strSourceSubDir="${strSourceFullDir##$strSourcePath/}"
				echo "Source File: .../$strSourceSubDir/$strSourceFileName"
				strInSubDir=true
			fi


			# Announce if a file is too small to bother organising.
			if [ $strSkipSampleFiles = true ] && [[ "${strSourceFileName,,}" = *"sample"* ]]
			then
				echo "No Action: The Filenname containts the word   sample   and will be skipped."
				# Skip rest of this loop iteration
				continue
			fi

			# Get file size of the current file in the loop
			IFS=''
			intFileSizeInBytes=($(stat -c %s $strSourceFile))

			# Announce if a file is too small to bother organising.
			if [ $intFileSizeInBytes -le $intFileSizeToIgnore ]
			then
				echo "No Action: File is smaller or equal to $intMinFileSizeToIgnoreInMB MB."
				# Skip rest of this particular loop iteration
				continue
			fi

			# Check file name for exclusion strings
			if [ $strCheckForExcludes = true ]
			then
				IFS=$'\n'
				for strExcludeString in "${arrExcludesList[@]}"
				do :
					if [[ "${strSourceFileName,,}" = *"${strExcludeString,,}"* ]]
					then
						echo "Skipping mvkmerge: The filename contains a match with the following exclusion string - $strExcludeString"
						strActionFileMoveOnly=true
					fi
				done
			fi

			### Check if the file falls inside the exclusion file sizes
			if [ $intFileSizeInBytes -gt $intFileSizeToIgnore ] && [ $intFileSizeInBytes -le $intFileSizeToTriggerSubtitleRemoval ]
			then
				# Move the file into the required directory
				echo "Skipping mvkmerge: File is smaller than the Trigger size $intMinFileSizeToTriggerSubtitleRemovalInGB GB"
				strActionFileMoveOnly=true
			fi

			# Move the file into the required directory.
			if [ $strActionFileMoveOnly = true ]
			then
				if [ $strOverWriteTarget = true ] || [ ! -e "$strTargetDirAndFileName" ]
				then
					echo "Moving From: $(dirname $strSourceFile)"
					echo "         To: $(dirname $strTargetDirAndFileName)"
					if [ $strWhatIfMode = false ]
					then
						mv -f "$strSourceFile" "$strTargetDirAndFileName"
						if [ $? -gt 0 ]
						then
							echo "ERROR-04: mv -f $strSourceFile $strTargetDirAndFileName"
							exit 1
						fi
					else
						echo "*** What If:  mv -f $strSourceFile $strTargetDirAndFileName"
					fi
				elif [ $strOverWriteTarget = false ] && [ -e "$strTargetDirAndFileName" ]
				then
					echo "No Action: Target already exists $strTargetDirAndFileName"
				fi
			fi
 
			### CCheck if the subtitle streams should be removed before the file is moved into the required directory.
			if [[ $strActionFileMoveOnly = false ]]
			then
				# Set the location and file name for mvkmerge to output to
				strMKVMergeOutputDirAndFileName=($strTargetDirMKVMergeTemp/$strSourceFileName)
			
				# Use mkmerge to remove the subtitles. This will create a copy of the video file which will be moved after it has been processed.
				echo "MKVMerge   : Removing Subtitles . . ."
				if [ $strWhatIfMode = false ]
				then
					# Make sure the output files does not exist.
					if [ -e "$strMKVMergeOutputDirAndFileName" ]
					then
						echo "Removing previous output file from the mkvtemp directory"
						rm -f "$strMKVMergeOutputDirAndFileName"
						if [ $? -gt 0 ]
						then
							echo "ERROR-17: rm -f $strMKVMergeOutputDirAndFileName"
							exit 1
						fi
					fi

					# Create the temp dir if not exist
					if [ ! -e "$strTargetDirMKVMergeTemp" ]
					then
						echo "Creating mkvmerge temp directory: $strTargetDirMKVMergeTemp"
						mkdir -p "$strTargetDirMKVMergeTemp"
						if [ $? -gt 0 ]
						then
							echo "ERROR-15: mkdir -p $strTargetDirMKVMergeTemp"
							exit 1
						fi
					fi

					if [ $strManualTrackSelection = true ]
					then
						fSelectListOfTracksToInclude "$strSourceFile"
						if [ $strSkipThisFile = false ]
						then
							mkvmerge -o "$strMKVMergeOutputDirAndFileName" --audio-tracks $strParamAudioTracks --video-tracks $strParamVideoTracks --subtitle-tracks $strParamSubtitleTracks "$strSourceFile"
						else
							echo -e "\nNo Action: This file will be skipped."
							continue
						fi
					elif [ $strKeepEnglishAudioAndSubtitles = true ] && [ $strManualTrackSelection = false ]
					then
						mkvmerge -o "$strMKVMergeOutputDirAndFileName" --subtitle-tracks und,eng --audio-tracks und,eng "$strSourceFile"
					else
						mkvmerge -o "$strMKVMergeOutputDirAndFileName" --no-subtitles "$strSourceFile"
					fi


					if [ $? -gt 0 ]
					then
						echo "ERROR-05: mkvmerge - invalid parameters"
						exit 1
					fi
				else
					echo "*** What If: mkvmerge outfile: $strMKVMergeOutputDirAndFileName   sourcefile: $strSourceFile"
				fi


				# Rename the original source file to include .WithSRT in the name.
				IFS=''
				case $strSourceFile in
					*.mkv)
						strSourceFileRenamed="$(dirname $strSourceFile)/$(basename -s .mkv $strSourceFile).WithSRT.mkv"
						;;
					*.mp4)
						strSourceFileRenamed="$(dirname $strSourceFile)/$(basename -s .mp4 $strSourceFile).WithSRT.mp4"
						;;
				esac
				
				
				echo "Rename Original To: $(basename $strSourceFileRenamed)"
				if [ $strWhatIfMode = false ]
				then
					mv -f "$strSourceFile" "$strSourceFileRenamed"
					if [ $? -gt 0 ]
					then
						echo "ERROR-18: mv $strSourceFile $strSourceFileRenamed"
						exit 1
					fi
				else
					echo "*** What If: mv $strSourceFile $strSourceFileRenamed"
				fi


				# Move the file into the required directory.
				if [ $strOverWriteTarget = true ] || [ ! -e "$strTargetDirAndFileName" ]
				then
					echo "Moving From: $(dirname $strMKVMergeOutputDirAndFileName)"
					echo "         To: $(dirname $strTargetDirAndFileName)"
					if [ $strWhatIfMode = false ]
					then
						mv -f "$strMKVMergeOutputDirAndFileName" "$strTargetDirAndFileName"
						if [ $? -gt 0 ]
						then
							echo "ERROR-06: mv -f $strMKVMergeOutputDirAndFileName $strTargetDirAndFileName"
							exit 1
						fi
					else
						echo "*** What If: mv $strMKVMergeOutputDirAndFileName $strTargetDirAndFileName"
					fi
				elif [ $strOverWriteTarget = false ] && [ -e "$strTargetDirAndFileName" ]
				then
					echo "No Action: Target already exists $strTargetDirAndFileName"
				fi
			fi

			if [ $strInSubDir = false ]
			then
				IFS=$'\n'
				## Add the Source file to the list of files to delete
				if [ $strSourceFileRenamed = false ]
				then
					arrFilesToDelete+=("$strSourceFile")
				else
					arrFilesToDelete+=("$strSourceFileRenamed")
				fi
			else
				## Add the sub dir to the list of dirs to delete.
				IFS=$'\n'
				arrDirsToDelete+=("$strSourcePath/${strSourceSubDir[0]}")
			fi

		done


		### If Deleting source option selected
		if [ $strDeleteSource = true ]
		then

			# Delete the directories left behind.
			IFS=$'\n'
			if [ ${#arrDirsToDelete[@]} -gt 0 ]
			then
				# Display significant event seperator
				echo ""
				echo "-------------------------------------------------------------------------------"
				echo ""
				echo "Deleting remaining directories . . ."
				for strDirectoryToDelete in ${arrDirsToDelete[@]}
				do
					if [ -e "$strDirectoryToDelete" ]
					then
						echo "Deleting Dir  : $strDirectoryToDelete"
						if [ $strWhatIfMode = false ]
						then
							rm -r -f "$strDirectoryToDelete"
							if [ $? -gt 0 ]
							then
								echo "ERROR-07: rm -r -f $strDirectoryToDelete"
								exit 1
							fi
						else
							echo "*** What If: rm -r -f $strDirectoryToDelete"
						fi
					fi
				done
			fi


			
			# Delete Files left behind
			IFS=$'\n'
			if [ ${#arrFilesToDelete[@]} -gt 0 ]
			then
				# Display significant event seperator
				echo ""
				echo "-------------------------------------------------------------------------------"
				echo ""
				echo "Deleting remaining files . . ."
				for strFileToDelete in ${arrFilesToDelete[@]}
				do
					echo "Deleting File : $strFileToDelete"
					if [ $strWhatIfMode = false ] && [ -e "$strFileToDelete" ]
					then 
						rm -f "$strFileToDelete"
						if [ $? -gt 0 ]
						then
							echo "ERROR-08: rm -f $strFileToDelete"
							exit 1
						fi
					else
						echo "*** What If: rm -f $strFileToDelete"
					fi
				done
			fi
		fi

		# It is possible that move files have appeared in the source dir since the script started.
		# Set to do another loop. Only applies in auto mode.
		strDoTheloop=true
		
	else
	
		# Diplay count of found files.
		echo ""
		echo "Files found to Process: 0"
		
		# Set to NOT do another loop. Only applies in auto mode.
		strDoTheloop=false
	fi

}


function fProcessOneFile() {
	IFS=''
	# Diplay the settings and how many files will be processed.
	echo ""
	echo "==============================================================================="
	echo ""
	echo "Source File      : $strSourceFile"
	echo "Overwrite Target : $strOverWriteTarget"
	echo "Delete Source    : $strDeleteSource"
	echo "Keep English Subs: $strKeepEnglishAudioAndSubtitles"


	# Split the file name from from the dir path in strSourceFile
	strSourceFileName=$(basename $strSourceFile)

	# Setup the destination paths and include the file name.
	strTargetFileNameAndPath=($strTargetDir/$strSourceFileName)

	if [ $strOverWriteTarget = true ] || [ ! -e "$strTargetFileNameAndPath" ]
	then
		echo "ERROR-19: Target file already exists - $strTargetFileNameAndPath"
		echo "          Move or rename that file or use the -o switch to overwrite it automatically"
		exit 1
	fi

	# Set the location and file name for mvkmerge to output to
	strMKVMergeOutputDirAndFileName=($strTargetDirMKVMergeTemp/$strSourceFileName)

	# Use mkmerge to remove the subtitles. This will create a copy of the video file which will be moved after it has been processed.
	echo "Removing Subtitles : $strSourceFile"
	if [ $strWhatIfMode = false ]
	then
		if [ -e "$strMKVMergeOutputDirAndFileName" ]
		then
			rm -f "$strMKVMergeOutputDirAndFileName"
			if [ $? -gt 0 ]
			then
				echo "ERROR-09: rm -f $strMKVMergeOutputDirAndFileName"
				exit 1
			fi
		fi

		# Create the temp dir if not exist
		if [ ! -e "$strTargetDirMKVMergeTemp" ]
		then
			echo "Creating mkvmerge temp directory: $strTargetDirMKVMergeTemp"
			mkdir -p "$strTargetDirMKVMergeTemp"
			if [ $? -gt 0 ]
			then
				echo "ERROR-16: mkdir -p $strTargetDirMKVMergeTemp"
				exit 1
			fi
		fi

		if [ $strManualTrackSelection = true ]
		then
			fSelectListOfTracksToInclude "$strSourceFile"
			if [ $strSkipThisFile = false ]
			then
				mkvmerge -o "$strMKVMergeOutputDirAndFileName" --audio-tracks $strParamAudioTracks --video-tracks $strParamVideoTracks --subtitle-tracks $strParamSubtitleTracks "$strSourceFile"
			else
				echo "No Action: This file will be skipped."
			fi
		elif [ $strKeepEnglishAudioAndSubtitles = true ] && [ $strManualTrackSelection = false ]
		then
			mkvmerge -o "$strMKVMergeOutputDirAndFileName" --subtitle-tracks und,eng --audio-tracks und,eng "$strSourceFile"
		else
			mkvmerge -o "$strMKVMergeOutputDirAndFileName" --no-subtitles "$strSourceFile"
		fi


		if [ $? -gt 0 ]
		then
			echo "ERROR-10: mkvmerge - invalid parameters"
			exit 1
		fi
	else
		echo "*** What If: mkvmerge outfile: $strMKVMergeOutputDirAndFileName   sourcefile: $strSourceFile"
	fi

	# Rename the original source file to include .WithSRT in the name.
	IFS=''
	case $strSourceFile in
		*.mkv)
			strSourceFileRenamed="$(dirname $strSourceFile)/$(basename -s .mkv $strSourceFile).WithSRT.mkv"
			;;
		*.mp4)
			strSourceFileRenamed="$(dirname $strSourceFile)/$(basename -s .mp4 $strSourceFile).WithSRT.mp4"
			;;
	esac
	
	echo "Rename Original To: $(basename $strSourceFileRenamed)"
	if [ $strWhatIfMode = false ]
	then
		mv -f "$strSourceFile" "$strSourceFileRenamed"
		if [ $? -gt 0 ]
		then
			echo "ERROR-18: mv $strSourceFile $strSourceFileRenamed"
			exit 1
		fi
	else
		echo "*** What If: mv $strSourceFile $strSourceFileRenamed"
	fi


	# Move the file into the required directory.
	echo "Moving From : $strMKVMergeOutputDirAndFileName"
	echo "         To : $strTargetFileNameAndPath"
	if [ $strOverWriteTarget = true ] || [ ! -e "$strTargetFileNameAndPath" ]
	then
		if [ $strWhatIfMode = false ]
		then 
			mv -f "$strMKVMergeOutputDirAndFileName" "$strTargetFileNameAndPath"
			if [ $? -gt 0 ]
			then
				echo "ERROR-11: mv -f $strMKVMergeOutputDirAndFileName $strTargetFileNameAndPath"
				exit 1
			fi
		else
			echo "*** What If: mv -f $strMKVMergeOutputDirAndFileName $strTargetFileNameAndPath"
		fi
	elif [ $strOverWriteTarget = false ] || [ -e "$strTargetFileNameAndPath" ]
	then
		echo "ERROR-06: Target file already exists - $strTargetFileNameAndPath"
		echo "          Move or rename that file or use the -o switch to overwrite it automatically"
		echo "          mkvmerge has already create copy with SRT streams removed. You  can  move this by hand."
		echo "          $strMKVMergeOutputDirAndFileName"
		exit 1
	fi

	# If Delete source option selected
	if [ $strDeleteSource = true ]
	then
		if [ $strWhatIfMode = false ]
		then 
			rm -f "$strSourceFileRenamed"
			if [ $? -gt 0 ]
			then
				echo "ERROR-12: rm -f $strSourceFileRenamed"
				exit 1
			fi
		else
			echo "*** What If: rm -f $strSourceFileRenamed"
		fi
	fi
}




### MAIN ###############################################################################################################

# Initial User greeting
echo ""
echo "Curate-Videos  $intVerion"
echo ""

# Script assumes you are running in commandline mode by default.
ApplyCmdLineDefaultSettings

# Process the command line options
strValidCmdLineOptions=":hwaeEmSoxrd:s:t:f:T:z"
while getopts "$strValidCmdLineOptions" arrReceivedCmdLineOptions
do
	case ${arrReceivedCmdLineOptions} in
	h )
		# Display the help
		fDisplayUsage
		exit 0
		;;
	w )
		# Enable What If Mode
		strWhatIfMode=true
		;;
	a )
		# run in Auto Mode ignores the other switches except for -w
		strExecutionMode=auto
		;;
	e )
		# Keep English Audio and Subtitles
		strKeepEnglishAudioAndSubtitles=true
		;;
	E )
		# Check the specified Excludes file exists
		if [ ! -f "$OPTARG" ]
		then
			echo "Invalid Option: The specified excludes file could not be found."
			strInvalidOptions=true
		fi
		strExcludesListFileNameAndPath="$OPTARG"
		strCheckForExcludes=true
		;;
	m )
		# specify the filter for the match type
		strManualTrackSelection=true
		;;
	S )
		# Skip sample files
		strSkipSampleFiles=false
		;;
	o )
		# Overwrite files in target dir or the target file.
		strOverWriteTarget=true
		;;
	x )
		# Delete the source files/dirs (Careful with this one)
		read -r -p "Are you sure you want to delete the source Files / Directories [Y/N]? " strYesNo
		echo ""
		if [ ${strYesNo,,} = y ]
		then
			strDeleteSource=true
		else
			echo "ABORTED: User Said No!"
			exit 1
		fi
		;;
	d )
		# Define a max depth to recurse into.
		if [ $strRecurseSourceDir = true ]
		then
			echo "Invalid Option: d and r cannot be used together."
			strInvalidOptions=true
		fi
		strRecurseSourceDir=limited			
		strRecurseLimiterMaxDepth=$OPTARG
		;;
	r )
		# Recurse unlimited sub dirs
		if [ $strRecurseSourceDir = limited ]
		then
			echo "Invalid Option: r and d cannot be used together."
			strInvalidOptions=true
		fi
		strRecurseSourceDir=true
		;;
	s )
		# Specify the source dir / file
		if [ ! -f "$OPTARG" ] && [ ! -d "$OPTARG" ]
		then
			echo "Invalid Option: Bad Source file or directory"
			strInvalidOptions=true
		fi
		
		if [ "$OPTARG" = "./" ]
		then			
			echo "Invalid Option: do not use ./ - Use . or do not use -s at all if you are refering to the current directory."
			strInvalidOptions=true
		fi
		
		if [ -f "$OPTARG" ]
		then		
			strFileSelectionMode=file
			strSourceFile="$OPTARG"
			if [ ! $strRecurseSourceDir = false ]
			then
				echo "Invalid Option: optiones r and d cannot be used if a single file is specified as the source. You can only recurse a directory."
				strInvalidOptions=true
			fi
		fi
		
		if [ -d "$OPTARG" ]
		then			
			strFileSelectionMode=dir
			strSourcePath="$OPTARG"
		fi	
		;;
	t )
		# Specify the Target dir
		if [ ! -d "$OPTARG" ]
		then
			echo "Invalid Option: Bad Target Directory"
			strInvalidOptions=true
		fi
		strTargetDir="$OPTARG"
		;;
	f )
		# specify the filter for the match type
		strFilterMatchType="$OPTARG"
		;;
	T )
		# specify the mkvmerge temp directory
		if [ ! -d "$OPTARG" ]
		then
			echo "Invalid Option: Bad Temp directory"
			strInvalidOptions=true
		fi
		strTargetDirMKVMergeTemp="$OPTARG"
		;;
	\? )
		# Error trap
		echo "Invalid option: $OPTARG"
		strInvalidOptions=true
		;;
	: )
		# Error trap
		echo "Invalid option: $OPTARG requires an argument"
		strInvalidOptions=true
		;;
	esac
done

# If any invalid options where detected then exit here.
if [ $strInvalidOptions ]
then
	echo ""
	echo "For usage information use: curate-videos -h"
	echo ""
	exit 1
fi

if [ $strExecutionMode = auto ]
then
	# At this point all looks good. Now we executee the loop.
	echo "Automated exection started . . ."

	### Script Mode = Auto - The script will use the values in the User Settings variables and run without user interaction.
	ApplyAutoModeSettings
	ApplyCommonSystemSettings

	### Check the paths defined in the user settings are all correct
	fCheckPaths

	### Get the list exclude strings from the excludes file
	IFS=$'\n'
	arrExcludesList=($(cat "$strExcludesListFileNameAndPath"))

	### Check if this script is already running
	strScriptName=$(basename $BASH_SOURCE)
	intNumOfScriptProcs=$(pidof -x "$strScriptName" | tr " " "\n" | wc -l)
	if [ $intNumOfScriptProcs -gt 2 ]
	then
		echo ""
		echo "Script is already running! - No further actions taken."
		echo ""
		echo "curate-videos.sh cannot start in Audo Mode because it is currently running." | systemd-cat -t curate-videos -p notice
		exit
	fi

	# Call the log hanlder function to setup the log file
	fHandleLogs

	# Starting logging all output to file
	exec > >(tee -a "$strLogFileNameAndPath") 2>&1

	# Initials the Loop Counter
	intLoopCounter=1

	# Start the Looper
	until [ $strDoTheloop = false ] || [ $intLoopCounter -gt $intLoopLimit ]
	do
		echo ""
		echo "Starting Loop # $intLoopCounter"
		
		if [ ! $strTargetDir = none ]
		then
			# Process source directory into single target directory
			strFilterMatchType=all
			fProcessFilesInDir
		else
			# Process source files into Shows target directory
			strTargetDir="$strTargetDirShows"
			strFilterMatchType=shows
			fProcessFilesInDir
			
			# Process source files into Films target directory
			strTargetDir="$strTargetDirFilms"
			strFilterMatchType=films
			fProcessFilesInDir
		fi

		# Increment the Loop counter
		let "intLoopCounter+=1"
	done

elif [ $strExecutionMode = commandline ]
then
	ApplyCommonSystemSettings

	if [ "$strTargetDirMKVMergeTemp" = "$strTargetDir" ] || [ "$strTargetDirMKVMergeTemp" = "$strSourcePath" ]
	then
		echo "ERROR-20: The MKVmerge temp directory cannot be the same as the source or target directories"
		exit 1
	fi

	### Script Mode = CommmandLine - The script will use the values provided as command line switches then run as instructed.
	echo "Command Line exection started . . ."
	
	### Process the file(s)
	case $strFileSelectionMode in
		file )
			fProcessOneFile
			;;
		dir )
			fProcessFilesInDir
			;;
	esac

	# Remove the temp dir, but only if empty.
	if [ -e "$strTargetDirMKVMergeTemp" ]
	then
		strCountFilesLeftInMKVTempDir=$(find "$strTargetDirMKVMergeTemp")
		IFS=$'\n'
		if [ ${#strCountFilesLeftInMKVTempDir[@]} -le 1 ]
		then
			echo ""
			echo "Deleting mkvmerge temp directory: $strTargetDirMKVMergeTemp"
			rm -f -r "$strTargetDirMKVMergeTemp"
			if [ $? -gt 0 ]
			then
				echo "WARNING-04: rm -f -r $strTargetDirMKVMergeTemp"
			fi
		else
			echo "WARNING-05: mkvtemp directory not empty - $strTargetDirMKVMergeTemp"
		fi
	fi

else
	echo ""
	echo "Bad Execution Mode. Did you edit the script?"
	exit 1
fi

### END ###############################################################################################################

echo ""
echo "Done."
echo ""
exit 0
