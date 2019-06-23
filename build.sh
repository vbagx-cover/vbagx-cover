#!/bin/sh
#
# builds the source tree in a docker environment


# utility function for writing to stderr
__echo_to_stderr() {
    if [ ${?} -ne 0 ]
    then
        return 1
    fi

    echo "${@}" 1>&2
    return 0
}

# tests whether the specified executables are in the path
check_executables_are_available() {
    for EXECUTABLE do
        EXECUTABLE_PATH="$(which "${EXECUTABLE}")"
        if [ ${?} -ne 0 ]
        then
            __echo_to_stderr "${EXECUTABLE} is not installed."
            return 1
        fi
    done

    return 0
}

# writes the script directory to stdout
get_script_directory() {
    echo "$(readlink --canonicalize "$(dirname "${0}" 2> /dev/null)" 2> /dev/null)"
    EXIT_CODE=${?}
    if [ ${EXIT_CODE} -ne 0 ]
    then
        __echo_to_stderr "Cannot get script directory. Error: ${EXIT_CODE}"
        return 1
    fi

    return 0
}

# writes the current directory to stdout
get_current_directory() {
    echo "$(pwd 2> /dev/null)"
    EXIT_CODE=${?}
    if [ ${EXIT_CODE} -ne 0 ]
    then
        __echo_to_stderr "Cannot get current directory. Error: ${EXIT_CODE}"
        return 1
    fi

    return 0
}

# changes directory to the directory specified by the first argument
change_directory() {
    cd "${1}" 2> /dev/null
    EXIT_CODE=${?}
    if [ ${EXIT_CODE} -ne 0 ]
    then
        __echo_to_stderr "Cannot change directory to ${1}. Error: ${EXIT_CODE}"
        return 1
    fi

    return 0
}

# writes the current git tag or revision, prioritised in that order, to stdout
get_source_revision() {
    GIT_REVISION="$(git rev-parse --short HEAD)"
    EXIT_CODE=${?}
    if [ ${EXIT_CODE} -ne 0 ]
    then
        __echo_to_stderr "Cannot get git revision. Error: ${EXIT_CODE}"
        return 1
    fi

    GIT_TAG="$(git tag --points-at="${GIT_REVISION}")"
    EXIT_CODE=${?}
    if [ ${EXIT_CODE} -ne 0 ]
    then
        __echo_to_stderr "Cannot get git tag. Error: ${EXIT_CODE}"
        return 1
    fi

    if [ -n "${GIT_TAG}" ]
    then
        echo "${GIT_TAG}"
    else
        echo "${GIT_REVISION}"
    fi

    return 0
}

# removes the directory specified by the first argument
remove_directory() {
    rm -rf "${1}"
    EXIT_CODE=${?}
    if [ ${EXIT_CODE} -ne 0 ]
    then
        __echo_to_stderr "Cannot remove directory ${1}. Error: ${EXIT_CODE}"
        return 1
    fi

    return 0
}

# creates the directory specified by the first argument
create_directory() {
    mkdir --parents "${1}"
    EXIT_CODE=${?}
    if [ ${EXIT_CODE} -ne 0 ]
    then
        __echo_to_stderr "Cannot create directory ${1}. Error: ${EXIT_CODE}"
        return 1
    fi

    return 0
}

# checks whether the source revision specified by the first argument is a tag
is_untagged_build() {
    git tag | grep "${1}" 1> /dev/null
    if [ ${?} -ne 0 ]
    then
        return 0
    fi

    return 1
}

# check that necessary tooling is present
check_executables_are_available "readlink" "dirname" "pwd" "git" "rm" "mkdir" "docker" "grep" "zip"
if [ ${?} -ne 0 ]
then
    exit 1
fi

# get path of this script
SCRIPT_DIRECTORY=$(get_script_directory)
if [ ${?} -ne 0 ]
then
    exit 1
fi

# store the current directory
CURRENT_DIRECTORY=$(get_current_directory)
if [ ${?} -ne 0 ]
then
    exit 1
fi

# change to the script directory
change_directory "${SCRIPT_DIRECTORY}"
if [ ${?} -ne 0 ]
then
    exit 1
fi

# get the source revision
SOURCE_REVISION="$(get_source_revision)"
if [ ${?} -ne 0 ]
then
    # make best effort to return to the original directory
    change_directory "${CURRENT_DIRECTORY}"
    exit 1
fi

# compute the directory for the build output
BIN_DIRECTORY="${SCRIPT_DIRECTORY}/bin/${SOURCE_REVISION}"

# remove build output directory
remove_directory "${BIN_DIRECTORY}"
if [ ${?} -ne 0 ]
then
    # make best effort to return to the original directory
    change_directory "${CURRENT_DIRECTORY}"
    exit 1
fi

# make the build output directory
create_directory "${BIN_DIRECTORY}"
if [ ${?} -ne 0 ]
then
    # make best effort to return to the original directory
    change_directory "${CURRENT_DIRECTORY}"
    exit 1
fi

# do dockerised build
docker run \
    --rm \
    --mount "type=bind,source=${SCRIPT_DIRECTORY},target=/src/,readonly" \
    --mount "type=bind,source=${BIN_DIRECTORY},target=/tmp/bin/" \
    --workdir "/tmp/" \
    devkitpro/devkitppc:20190212 \
    /bin/sh -c \
        "cp -R /src/ . \
        && cd src \
        && make \
        && cp executables/* ../bin/"
if [ ${?} -ne 0 ]
then
    # make best effort to return to the original directory
    change_directory "${CURRENT_DIRECTORY}"
    exit 1
fi

# if this is not a tagged build then exit
if is_untagged_build "${SOURCE_REVISION}"
then
    # change back to the current directory
    change_directory "${CURRENT_DIRECTORY}"
    if [ ${?} -ne 0 ]
    then
        exit 1
    fi

    exit 0
fi

# TODO
# create distribution

# change back to the current directory
change_directory "${CURRENT_DIRECTORY}"
if [ ${?} -ne 0 ]
then
    exit 1
fi

exit 0
