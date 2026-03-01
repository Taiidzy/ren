#!/bin/bash

# Function to modify podspec file
modify_podspec() {
    local file_path=$1
    local name=$2
    local version=$3
    local default_subspec=$4

    # Check if file exists
    if [ ! -f "$file_path" ]; then
        echo "Error: File $file_path not found"
        return 1
    fi

    # Create temporary file
    temp_file=$(mktemp)

    # Modify name if provided
    if [ -n "$name" ]; then
        sed -E "s/s\.name[[:space:]]*=[[:space:]]*['\"][^'\"]*['\"]/s.name = '$name'/" "$file_path" > "$temp_file"
        mv "$temp_file" "$file_path"
    fi

    # Modify version if provided
    if [ -n "$version" ]; then
        sed -E "s/s\.version[[:space:]]*=[[:space:]]*['\"][^'\"]*['\"]/s.version = '$version'/" "$file_path" > "$temp_file"
        mv "$temp_file" "$file_path"
    fi

    # Modify default_subspec if provided
    if [ -n "$default_subspec" ]; then
        sed -E "s/s\.default_subspec[[:space:]]*=[[:space:]]*['\"][^'\"]*['\"]/s.default_subspec = '$default_subspec'/" "$file_path" > "$temp_file"
        mv "$temp_file" "$file_path"
    fi

    # Replace ffmpeg-kit-ios-*.zip and ffmpeg-kit-macos-*.zip with default_subspec
    sed -E "s/ffmpeg-kit-ios-[^[:space:]]+\.zip/ffmpeg-kit-ios-${default_subspec}.zip/g" "$file_path" > "$temp_file"
    mv "$temp_file" "$file_path"
    sed -E "s/ffmpeg-kit-macos-[^[:space:]]+\.zip/ffmpeg-kit-macos-${default_subspec}.zip/g" "$file_path" > "$temp_file"
    mv "$temp_file" "$file_path"

    # Rename file to directory + name.podspec
    local dir_path
    dir_path=$(dirname "$file_path")
    local new_file_path="$dir_path/$name.podspec"
    if [ "$file_path" != "$new_file_path" ]; then
        mv "$file_path" "$new_file_path"
        echo "Renamed $file_path to $new_file_path"
    else
        echo "No rename needed: $file_path already named $new_file_path"
    fi

    echo "Successfully modified $file_path"
}

# Function to modify Gradle file
modify_gradle() {
    local gradle_file=$1
    local flavor=$2
    local version=$3

    # Check if file exists
    if [ ! -f "$gradle_file" ]; then
        echo "Error: Gradle file $gradle_file not found"
        return 1
    fi

    # Create temporary file
    temp_file=$(mktemp)

    # Replace ffmpeg-kit flavor and version dynamically
    # Match any flavor and version, replace with new flavor and version
    sed -E "s/implementation 'com\.github\.meetleev\.ffmpeg-kit-prebuilt:ffmpeg-kit-[^:]+:[^']+'/implementation 'com.github.meetleev.ffmpeg-kit-prebuilt:ffmpeg-kit-${flavor}:${version}'/" "$gradle_file" > "$temp_file"

    # Check if sed made any changes
    if ! cmp -s "$gradle_file" "$temp_file"; then
        mv "$temp_file" "$gradle_file"
        echo "Successfully modified $gradle_file: Set ffmpeg-kit-$flavor:$version"
    else
        echo "No changes made to $gradle_file: Pattern not found or already updated"
        rm "$temp_file"
    fi
}

# Function to modify pubspec.yaml file
modify_pubspec() {
    local pubspec_file=$1
    local name=$2
    local version=$3

    # Check if file exists
    if [ ! -f "$pubspec_file" ]; then
        echo "Error: Pubspec file $pubspec_file not found"
        return 1
    fi

    # Create temporary file
    temp_file=$(mktemp)

    # Modify name
    sed -E "s/^name:[[:space:]]*.*/name: $name/" "$pubspec_file" > "$temp_file"
    mv "$temp_file" "$pubspec_file"

    # Modify version
    sed -E "s/^version:[[:space:]]*.*/version: $version/" "$pubspec_file" > "$temp_file"
    mv "$temp_file" "$pubspec_file"

    echo "Successfully modified $pubspec_file with name=$name, version=$version"
}

# Function to read name from pubspec.yaml
read_pubspec_name() {
    local pubspec_file=$1

    # Check if file exists
    if [ ! -f "$pubspec_file" ]; then
        echo "Error: Pubspec file $pubspec_file not found"
        exit 1
    fi

    # Extract name using grep and sed
    local name
    name=$(grep -E "^name:[[:space:]]*" "$pubspec_file" | sed -E "s/^name:[[:space:]]*([^[:space:]]+).*/\1/")
    
    if [ -z "$name" ]; then
        echo "Error: Could not extract name from $pubspec_file"
        exit 1
    fi

    echo "$name"
}

main() {
    local current_dir=$(pwd)
    # Define pubspec file path
    local pubspec_file="$current_dir/pubspec.yaml"
    # Read name from pubspec.yaml
    local flutter_package_name
    flutter_package_name=$(read_pubspec_name "$pubspec_file")
    # Define array of podspec files
    local podspec_files=("$current_dir/ios/${flutter_package_name}.podspec" "$current_dir/macos/${flutter_package_name}.podspec")
    # Define Gradle file path
    local gradle_file="$current_dir/android/build.gradle"
    local prefix='ffmpeg_kit_'
    local package_name="min_gpl"
    # package_name=''
    local is_lts=true
    local version='6.0.3'
    local aarVersion='6.0.3.1'
    local default_subspec='https'
    case "$package_name" in
        "min_gpl")
            default_subspec='min-gpl'
            gradle_flavor=$default_subspec
            if [ "$is_lts" = true ]; then
                version="$version-LTS"
                default_subspec="$default_subspec-lts"
                aarVersion="$aarVersion-LTS"
            fi
            ;;
        "min")
            # modify_podspec "$podspec_file" "b" "1.0" "core2"
            ;;
        *)
            prefix='ffmpeg_kit'
            gradle_flavor=$default_subspec
            if [ "$is_lts" = true ]; then
                version="$version-LTS"
                default_subspec="$default_subspec-lts"
                aarVersion="$aarVersion.LTS"
            fi
            ;;
    esac
    
    # Modify the Gradle file with dynamic flavor and version
    modify_gradle "$gradle_file" "$gradle_flavor" "$aarVersion"
    # Modify the pubspec.yaml file
    modify_pubspec "$pubspec_file" "${prefix}$package_name" "$version"
    for podspec_file in "${podspec_files[@]}"; do
        if [ -f "$podspec_file" ]; then
            modify_podspec "$podspec_file" "${prefix}$package_name" "$version" "$default_subspec"
        else
            echo "Warning: Podspec file $podspec_file not found, skipping"
        fi
    done
}

# Run main function
main