#!/bin/bash -e

if compgen -G "*.tar.gz" > /dev/null
then
    for file in *.tar.gz
    do
        echo "Processing ${file}"

        name="${file%.tar.gz}"
        game="$(echo "${file}" | cut -d\( -f 1 | awk '{$1=$1};1')"

        if [ -f "${name}.zip" ]
        then
            echo "Completed file already exists at '${name}.zip'"
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

        echo "Decompressing file '${file}'"
        tar -I pigz -xvf "${file}"
        echo "Decompression complete"

        if compgen -G "*.iso" > /dev/null
        then
            for iso in  *.iso
            do
                echo "Zipping file '${iso}'"
                zip "${iso%.iso}.zip" "${iso}"
                echo "Zipped to '${iso%.iso}.zip'"
            done
        fi

        rm -fv *.iso "${file}"

        echo "Finished processing '${file}'"
    done
else
    echo "No .tar.gz files found."
fi

