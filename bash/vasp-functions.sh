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

sort_atoms() {
    local input_file

    # Check for CONTCAR first, then POSCAR
    if [[ -f "CONTCAR" ]]; then
        input_file="CONTCAR"
    elif [[ -f "POSCAR" ]]; then
        input_file="POSCAR"
    else
        echo "Neither CONTCAR nor POSCAR file found."
        return 1
    fi

    echo "Indices and identities of atoms in $input_file sorted by height (z-coordinate):"

    # Read the atom identities (line 5)
    local atom_identities
    read -r line < <(sed -n '6p' "$input_file")
    atom_identities=($line)

    # Read the number of each atom type (line 6)
    local atom_counts
    read -r line < <(sed -n '7p' "$input_file")
    atom_counts=($line)

    # Read the Cartesian coordinates (starting from line 8)
    local coords_start_line=10
    local coords=()
    local index=1

    for i in "${!atom_identities[@]}"; do
        local count=${atom_counts[$i]}
        for ((j=0; j<count; j++)); do
            read -r coord_line < <(sed -n "$((coords_start_line + index - 1))p" "$input_file")
            coords+=("$index ${atom_identities[$i]} $(echo $coord_line | awk '{print $3}')")  # Store index, identity, and z-coordinate
            ((index++))
        done
    done

    # Sort by z-coordinate (third column)
    printf "%s\n" "${coords[@]}" | sort -k3,3n | while read -r sorted_line; do
        local idx identity z_coord
        read -r idx identity z_coord <<< "$sorted_line"
        printf "$idx\t$identity\t$z_coord\n"
    done

}
