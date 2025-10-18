#!/usr/bin/env bash
set -euo pipefail

MAX_ATTEMPTS=100
KEEP_FILES=0
DIFF_FLAGS="-u"

DATA_FILE="data.txt"
ANS_FILE="ans.txt"
TEST_FILE="test.txt"
DIFF_CASE_FILE="diff_case.txt"

if [ -f "$DIFF_CASE_FILE" ]; then
    rm "$DIFF_CASE_FILE"
fi

usage() {
    echo "Usage: $0 [options]"
    echo "  -n, --max-attempts <number>  Set maximum test attempts (default: $MAX_ATTEMPTS)"
    echo "  -k, --keep-files             Keep diff_case.txt when counterexample found (default: delete)"
    echo "  -d, --diff-flags <flags>     Diff flags like -bB to ignore spaces (default: '$DIFF_FLAGS')"
    echo "  -h, --help                   Show this help message"
    exit 0
}

replace_spaces_with_dots() {
    local input_file="$1"
    sed -e 's/ /./g' "$input_file"
}

create_diff_case_file() {
    local attempt=$1
    local diff_file="$DIFF_CASE_FILE"

    > "$diff_file"

    echo "┌───────────────────────────────────────────────────────┐" >> "$diff_file"
    echo "│          Counterexample Found - Attempt $attempt            │" >> "$diff_file"
    echo "├───────────────────────────────────────────────────────┤" >> "$diff_file"
    echo "│ Time: $(date)                 │" >> "$diff_file"
    echo "│ Config: Max attempts=$MAX_ATTEMPTS, diff flags='$DIFF_FLAGS'             │" >> "$diff_file"
    echo "└───────────────────────────────────────────────────────┘" >> "$diff_file"
    echo "" >> "$diff_file"

    echo " Test Data ($DATA_FILE):" >> "$diff_file"
    echo "─────────────────────────────────────────────────────────" >> "$diff_file"
    cat $DATA_FILE >> $diff_file
    echo "" >> "$diff_file"

    echo " Expected Output ($ANS_FILE) [spaces as '.']:" >> "$diff_file"
    echo "─────────────────────────────────────────────────────────" >> "$diff_file"
    replace_spaces_with_dots $ANS_FILE >> $diff_file
    echo "" >> "$diff_file"

    echo " Your Output ($TEST_FILE) [spaces as '.']:" >> "$diff_file"
    echo "─────────────────────────────────────────────────────────" >> "$diff_file"
    replace_spaces_with_dots $TEST_FILE >> "$diff_file"
    echo "" >> "$diff_file"

    echo " Diff Output (diff $DIFF_FLAGS):" >> "$diff_file"
    echo "─────────────────────────────────────────────────────────" >> "$diff_file"
    diff $DIFF_FLAGS "$ANS_FILE" "$TEST_FILE" | while IFS= read -r line; do
        echo "$line" >> "$diff_file"
    done
    echo "" >> "$diff_file"

    echo "┌───────────────────────────────────────────────────────┐" >> "$diff_file"
    echo "│                 Test Finished                        │" >> "$diff_file"
    echo "└───────────────────────────────────────────────────────┘" >> "$diff_file"
}

cleanup() {
    echo ""
    echo "  Interrupt detected, cleaning up..."
    rm -f *.out "$DATA_FILE" "$ANS_FILE" "$TEST_FILE"
    if [[ $KEEP_FILES -eq 0 ]] && [[ -f "$DIFF_CASE_FILE" ]]; then
        rm -f "$DIFF_CASE_FILE"
        echo "  All temporary files deleted."
    elif [[ -f "$DIFF_CASE_FILE" ]]; then
        echo "  Diff case file preserved: $DIFF_CASE_FILE"
    else
        echo "  Temporary files deleted."
    fi
    exit 1
}

trap cleanup SIGINT

while getopts "n:kd:h-:" opt; do
    case "$opt" in
        n)
            MAX_ATTEMPTS="$OPTARG"
            ;;
        k)
            KEEP_FILES=1
            ;;
        d)
            DIFF_FLAGS="$OPTARG"
            ;;
        h)
            usage
            ;;
        -)
            case "${OPTARG}" in
                max-attempts)
                    MAX_ATTEMPTS="${!OPTIND}"; OPTIND=$((OPTIND + 1))
                    ;;
                keep-files)
                    KEEP_FILES=1
                    ;;
                diff-flags)
                    DIFF_FLAGS="${!OPTIND}"; OPTIND=$((OPTIND + 1))
                    ;;
                help)
                    usage
                    ;;
                *)
                    echo "Error: Unknown long option '--${OPTARG}'" >&2
                    usage
                    ;;
            esac
            ;;
        \?)
            echo "Error: Unknown option '-$OPTARG'" >&2
            usage
            ;;
        :)
            echo "Error: Option '-$OPTARG' requires an argument" >&2
            usage
            ;;
    esac
done
shift $((OPTIND - 1))

echo "  Compiling programs..."
if ! g++ -std=c++17 -O3 ans.cpp -o ans.out; then
    echo "  Compilation failed: ans.cpp"
    exit 1
fi
if ! g++ -std=c++17 -O3 test.cpp -o test.out; then
    echo "  Compilation failed: test.cpp"
    exit 1
fi
if ! g++ -std=c++17 -O3 data.cpp -o data.out; then
    echo "  Compilation failed: data.cpp"
    exit 1
fi
echo "  All programs compiled successfully!"
echo "--------------------"

echo "  Starting automated testing..."
echo "  Press Ctrl+C to interrupt and cleanup."
echo "  Config: Max attempts=$MAX_ATTEMPTS, Keep files=$([ $KEEP_FILES -eq 1 ] && echo "Yes" || echo "No"), Diff flags='$DIFF_FLAGS'"
echo "--------------------"

count=0
found_counterexample=0

while (( count < MAX_ATTEMPTS )); do
    ((++count))

    echo "Running test attempt $count..."

    echo "  - Generating test data..."
    if ! ./data.out > "$DATA_FILE"; then
        echo "  Data generator crashed!"
        exit 1
    fi

    echo "  - Running reference program (ans.out)..."
    if ! ./ans.out < "$DATA_FILE" > "$ANS_FILE"; then
        echo "  Reference program crashed!"
        exit 1
    fi
    
    echo "  - Running your program (test.out)..."
    if ! ./test.out < "$DATA_FILE" > "$TEST_FILE"; then
        echo "  Your program crashed!"
        exit 1
    fi

    echo "  - Comparing outputs (using: $DIFF_FLAGS)..."
    if ! eval "diff $DIFF_FLAGS \"$ANS_FILE\" \"$TEST_FILE\"" > /dev/null; then
        found_counterexample=1
        echo "--------------------"
        echo "  Counterexample found! On attempt $count."
        
        create_diff_case_file "$count" || true
        echo "  Diff case saved to: $DIFF_CASE_FILE"
        echo ""
        echo " Diff preview:"
        echo "─────────────────────────────────────────────────────────────────────"
        eval "diff $DIFF_FLAGS \"$ANS_FILE\" \"$TEST_FILE\" | head -20" || true
        if eval "diff $DIFF_FLAGS \"$ANS_FILE\" \"$TEST_FILE\" | head -21 | tail -1" > /dev/null 2>&1; then
            echo "   ... (full diff in $DIFF_CASE_FILE)"
        fi
        echo "─────────────────────────────────────────────────────────────────────"
        
        rm -f *.out "$DATA_FILE" "$ANS_FILE" "$TEST_FILE"
        break
    else
        echo "  - Attempt $count: Outputs match."
    fi

    echo "--------------------"
done

if (( !found_counterexample )); then
    rm -f *.out "$DATA_FILE" "$ANS_FILE" "$TEST_FILE"
fi

if (( found_counterexample )); then
    echo ""
    if [[ $KEEP_FILES -eq 1 ]]; then
        echo "  Counterexample analysis complete. Diff report: $DIFF_CASE_FILE"
    else
        echo "  Counterexample found. Diff report will be deleted at exit."
        echo "   Use -k option to preserve the diff report file."
    fi
elif (( count >= MAX_ATTEMPTS )); then
    echo "  All $MAX_ATTEMPTS attempts completed. No counterexamples found. Test passed!"
fi

if [[ $KEEP_FILES -eq 0 ]] && [[ -f "$DIFF_CASE_FILE" ]]; then
    rm -f "$DIFF_CASE_FILE"
    echo "  All temporary files cleaned up."
elif [[ -f "$DIFF_CASE_FILE" ]]; then
    echo "  Diff report preserved: $DIFF_CASE_FILE"
    clear
    cat "$DIFF_CASE_FILE"
fi

echo "﫠  Script finished."
