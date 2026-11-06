#!/usr/bin/env bash

set -e # exit immediately if a command exits with a non-zero status
set -u # treat unset variables as an error

# see: MobileVLCKit cocoapods

find ${DEPS} -name "*.dylib" -type f | while read DYLIB; do
    echo "${DYLIB}"

    # create framework name: libavcodec.59.dylib -> Avcodec
    FRAMEWORK_NAME=$(basename $DYLIB .dylib | sed 's/\.[0-9]*$//' | sed 's/^lib//')
    FRAMEWORK_NAME="$(tr '[:lower:]' '[:upper:]' <<<${FRAMEWORK_NAME:0:1})${FRAMEWORK_NAME:1}"

    # framework dir
    FRAMEWORK_DIR="${OUTPUT_DIR}/${FRAMEWORK_NAME}.framework"

    if [ -d $FRAMEWORK_DIR ]; then
        # Duplicated framework because of versioned dylibs, just skip
        continue
    fi

    # determine archs
    ARCHS=$(lipo -archs "${DYLIB}")

    # determine lowest min os version across archs
    for ARCH in ${ARCHS}; do
        # determine min os version for the current arch
        ARCH_MIN_OS_VERSION=$(vtool -arch ${ARCH} -show-build "${DYLIB}" | grep minos | cut -d ' ' -f6)
        if [ -z "${ARCH_MIN_OS_VERSION}" ]; then
            ARCH_MIN_OS_VERSION=$(vtool -arch ${ARCH} -show-build "${DYLIB}" | grep version | cut -d ' ' -f4)
        fi

        # if not found throw an error
        if [ -z "${ARCH_MIN_OS_VERSION}" ]; then
            echo "Unable to find min os version for ${ARCH}"
            exit 1
        fi

        # if $MIN_OS_VERSION is null or greater than $ARCH_MIN_OS_VERSION replace it
        MIN_OS_VERSION=
        if [ -z "${MIN_OS_VERSION}" ] || (($(bc -l <<<"${MIN_OS_VERSION} > ${ARCH_MIN_OS_VERSION}"))); then
            MIN_OS_VERSION=${ARCH_MIN_OS_VERSION}
        fi
    done

    # copy dylib
    mkdir -p "${FRAMEWORK_DIR}"
    cp "${DYLIB}" "${FRAMEWORK_DIR}/${FRAMEWORK_NAME}"

    # replace DYLIB var
    DYLIB="${FRAMEWORK_DIR}/${FRAMEWORK_NAME}"

    # update dylib id
    NEW_ID="@rpath/${FRAMEWORK_NAME}.framework/${FRAMEWORK_NAME}"
    install_name_tool \
        -id "${NEW_ID}" "${DYLIB}" \
        2>/dev/null

    # update dylib dep paths
    otool -l "${DYLIB}" |
        grep " name " |
        cut -d " " -f11 |
        tail -n +2 |
        grep "@rpath" |
        while read DEP; do
            DEP_NAME=$(basename $DEP .dylib | sed 's/\.[0-9]*$//' | sed 's/^lib//')
            DEP_NAME="$(tr '[:lower:]' '[:upper:]' <<<${DEP_NAME:0:1})${DEP_NAME:1}"

            NEW_DEP="@rpath/${DEP_NAME}.framework/${DEP_NAME}"

            install_name_tool \
                -change "${DEP}" "${NEW_DEP}" \
                "${DYLIB}" \
                2>/dev/null
        done

    # Drop build-time LC_RPATH entries.
    # Changing install names above rewrites what dyld looks for, but the binary
    # still carries the LC_RPATH entries baked in at link time, i.e. absolute
    # paths into the Nix store such as /nix/store/<hash>-mk-pkg-libplacebo-*/
    # lib. Those are meaningless on a device and leak the build environment;
    # dyld also wastes time probing them before falling back. Remove every one
    # and replace it with the locations that actually exist at runtime: next to
    # the loading binary (@loader_path) and in the app bundle's Frameworks dir
    # (@executable_path/Frameworks).
    otool -l "${DYLIB}" |
        awk '$1 == "cmd" && $2 == "LC_RPATH" { in_rpath = 1; next }
             in_rpath && $1 == "path"          { print $2; in_rpath = 0 }' |
        while read RPATH; do
            # never strip the ones we are about to add
            case "${RPATH}" in
                @loader_path*|@executable_path*) continue ;;
            esac
            install_name_tool -delete_rpath "${RPATH}" "${DYLIB}" 2>/dev/null || true
        done

    install_name_tool -add_rpath "@loader_path" "${DYLIB}" 2>/dev/null || true
    install_name_tool -add_rpath "@executable_path/Frameworks" "${DYLIB}" 2>/dev/null || true

    # add Info.plist
    cp --no-preserve=mode ${INFO_PLIST_PATH} "${FRAMEWORK_DIR}/Info.plist"
    sed -i 's/${FRAMEWORK_NAME}/'${FRAMEWORK_NAME}'/g' "${FRAMEWORK_DIR}/Info.plist"
    sed -i 's/${MIN_OS_VERSION}/'${MIN_OS_VERSION}'/g' "${FRAMEWORK_DIR}/Info.plist"
    plutil -convert binary1 "${FRAMEWORK_DIR}/Info.plist"

    # Mpv.framework needs headers and a module map to be importable as a Swift module
    if [ $FRAMEWORK_NAME == "Mpv" ]; then
        # copy headers
        mkdir -p "${FRAMEWORK_DIR}/Headers"
        cp --no-preserve=mode "${MPV_HEADERS_PATH}"/*.h "${FRAMEWORK_DIR}/Headers/"

        # generate the umbrella header (Mpv.h) re-exporting all of them
        for header_path in "${MPV_HEADERS_PATH}"/*.h; do
            header=$(basename "$header_path")
            echo "#import \"$header\"" >> "${FRAMEWORK_DIR}/Headers/Mpv.h"
        done

        # copy the module map to allow importing the framework as a named module
        mkdir -p "${FRAMEWORK_DIR}/Modules"
        cp --no-preserve=mode "${MPV_MODULE_MAP_PATH}" "${FRAMEWORK_DIR}/Modules/module.modulemap"
    fi
done
