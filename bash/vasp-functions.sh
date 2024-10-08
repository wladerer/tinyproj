#!/bin/bash

elements_from_poscar() {
    sed -n '6p' "$1" | awk '{for(i=1;i<=NF;i++) print $i}'
}

elements_from_potcar() {
    grep -i "VRHFIN" "$1" | awk -F '[=:]' '{print $2}' | sed 's/^[ \t]*//;s/[ \t]*$//'
}

lattice_parameters() {
        sed -n '3,5p' ${1:-./POSCAR} | awk '{printf "%.5f\n", sqrt($1^2 + $2^2 + $3^2)}'
}

checkVaspOrder() {
    local poscar_file="${1:-./POSCAR}"
    local potcar_file="${2:-./POTCAR}"
    local debug="${3:-false}"  # Debug flag, default is false
    
    local poscar_elements
    local potcar_elements

    poscar_elements=$(elements_from_poscar "$poscar_file")
    potcar_elements=$(elements_from_potcar "$potcar_file")
    
    if [ "$debug" = true ]; then
        echo "Debugging information:"
        echo ""
        echo "POSCAR file: $poscar_file"
        echo "POTCAR file: $potcar_file"
        echo "Elements extracted from POSCAR: $poscar_elements"
        echo "Elements extracted from POTCAR: $potcar_elements"   
    fi

    if [ "$poscar_elements" = "$potcar_elements" ]; then
        echo "Valid Poscar Potcar Combination"
        echo "Poscar order:" 
        for symbol in "${poscar_elements[@]}"; do
                echo $symbol
        done

        echo ""

        echo "Potcar order:"
        for symbol in "${poscar_elements[@]}"; do
                echo $symbol
        done

    else
        echo "Conflicting Element Order"
        echo "Poscar order: $poscar_elements"
        echo "Potcar order: $potcar_elements"
    fi
}

checkVaspInputs() {
    local dir="${1:-$(pwd)}"  # Default to current directory if no directory provided
    local files=("POSCAR" "POTCAR" "INCAR" "KPOINTS" )
    local missing_files=()

    for file in "${files[@]}"; do
        if [ ! -f "$dir/$file" ]; then
            missing_files+=("$file")
        fi
    done

    if [ ${#missing_files[@]} -eq 0 ]; then
        
        for file in ${files[@]}; do
                echo "Found $dir/$file"
        done
    else
        echo "The following files are missing in $dir:"
        printf '%s\n' "${missing_files[@]}"
    fi
}

checkVasp() {
    local dir="${1:-$(pwd)}"
    
    local poscar_file="${dir}/POSCAR"
    local potcar_file="${dir}/POTCAR"
    checkVaspInputs $dir
    checkVaspOrder $poscar_file $potcar_file

}

function cleanvasp() {
    find $1 -maxdepth 1 -type f ! \( -name 'POSCAR' -o -name 'POTCAR' -o -name 'INCAR' -o -name 'KPOINTS' -o -name '*.slurm' -o -name '*.sh' \) -exec rm {} +
}

scfplot() {
    idx=${1:-1}
    grep TOTEN OUTCAR | awk -v idx=$idx 'NR>idx {print NR-idx "," $(NF-1)}' | scatter -t "SCF Convergence"
}


geomplot() {
    idx=${1:-1}
    grep -a F OSZICAR | awk -v idx=$idx 'NR>idx {print NR-idx "," $(3)}' | scatter -t "Ionic Convergence"

}

forceplot() {
        idx=${1:-0}
        awk -v idx=$idx '
    /TOTAL-FORCE \(eV\/Angst\)/ { instances[++count] = ""; f = 1; next }
    f && /^-/ { f = 0 }
    f { instances[count] = instances[count] $0 "\n" }
    END {
        if (count > 0) {
            target_idx = count + idx;  # Calculate the target index
            if (target_idx > 0 && target_idx <= count) {
                print instances[target_idx];
            }
        }
    }
' OUTCAR | awk '/-----$/ { in_divider = !in_divider; next } in_divider { print }' | awk '{ print $(NF-2), $(NF-1), $NF }' | awk '{ magnitude = sqrt($1^2 + $2^2 + $3^2); print magnitude }' | hist  -x
}

find_converged() {
    find . -type f -name "OUTCAR" -exec grep -l "stopping struct" {} \; | xargs -I{} dirname {} 
}


sync_vasprun() {
        if [[ "$1" == "-h" || "$1" == "--help" ]]; then
        cat << EOF
            Usage: sync_vasprun <remote_path> <local_dest>
            
            Syncs the vasprun.xml file from a remote server to a local destination.
            
            Parameters:
              remote_path   The remote path in the format user@host:/path/to/remote
              local_dest    The local destination directory where files will be synced.
            
            Example:
              sync_vasprun user@remote.cluster.edu:/home/path/datadir ./
            EOF
                    return
    fi

    local remote_path="$1"  # Expect the first argument to include user and path
    local local_dest="$2"

    rsync -avz --include='*/' --include='vasprun.xml' --exclude='*' "$remote_path" "$local_dest"
}
