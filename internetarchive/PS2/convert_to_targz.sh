#!/bin/bash -e

if compgen -G "*.zip" > /dev/null
then
    for file in *.zip
    do
        echo "Processing ${file}"

        name="${file%.zip}"
        game="$(echo "${file}" | cut -d\( -f 1 | awk '{$1=$1};1')"

        if [ -f "${name}.tar.gz" ]
        then
            echo "Completed file already exists at '${name}.tar.gz'"
            rm -fv "${file}"
            echo "Finished processing '${file}'"
            continue
        fi

        if [[ "${file}" != "${game} (USA)"* ]] && compgen -G "${game} (USA)*" > /dev/null
        then
            echo "USA Version already exists at '$(ls "${game} (USA)"*)'"
            rm -fv "${file}"
            echo "Finished processing '${file}'"
            continue
        fi

        echo "Unzipping file '${file}'"
        unzip "${file}"
        echo "Unzip complete"

        if compgen -G "*.cue" > /dev/null
        then
            rm -fv *.cue
        fi

        if compgen -G "*.bin" > /dev/null
        then
            for bin in *.bin
            do
                mv -fv "${bin}" "${bin/.bin/.iso}"
            done
        fi

        if compgen -G "*.iso" > /dev/null
        then
            for iso in  *.iso
            do
                echo "Compressing file '${iso}'"
                tar -cf - "${iso}" | pigz -p 3 > "${iso%.iso}.tar.gz"
                echo "Compressed to '${iso%.iso}.tar.gz'"
            done
        fi

        rm -fv *.iso "${file}"

        echo "Finished processing '${file}'"
    done
else
    echo "No zip files found."
fi

