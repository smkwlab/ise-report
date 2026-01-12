#!/bin/bash
set -e

# Collect ISE report progress data from student repositories
# Output: progress-data.json

CSV_FILE="2024/students.csv"
OUTPUT_FILE="progress-data.json"

echo "=== Collecting ISE Report Progress Data ==="
echo ""

# Initialize output
echo "[]" > "$OUTPUT_FILE"

# Read student list from CSV (skip header)
STUDENT_COUNT=$(tail -n +2 "$CSV_FILE" | wc -l | tr -d ' ')
echo "Processing $STUDENT_COUNT students..."
echo ""

INDEX=0
tail -n +2 "$CSV_FILE" | while IFS=',' read -r STUDENT_ID_RAW NAME REPO_SUFFIX; do
    INDEX=$((INDEX + 1))

    # Convert student ID to lowercase with k prefix (23RS017 -> k23rs017)
    STUDENT_ID=$(echo "$STUDENT_ID_RAW" | tr '[:upper:]' '[:lower:]')
    STUDENT_ID="k${STUDENT_ID}"

    # Build repository name
    REPO="${STUDENT_ID}-${REPO_SUFFIX}"

    echo "[$INDEX/$STUDENT_COUNT] Processing: $REPO ($NAME)"

    # Initialize data
    FILE_SIZE="-"
    LAST_UPDATE="-"
    DRAFT_BRANCH="-"
    PR_STATUS="📝 作成中"
    REPO_EXISTS="true"

    # Check if repository exists
    if ! gh api "repos/smkwlab/$REPO" &>/dev/null; then
        echo "  ⚠ Repository not found"
        REPO_EXISTS="false"
        PR_STATUS="⏳ 未作成"
    fi

    if [ "$REPO_EXISTS" = "true" ]; then
        # Get current draft branch (most recent draft branch)
        DRAFT_BRANCH=$(gh api "repos/smkwlab/$REPO/branches" --jq \
            '[.[].name | select(test("^[0-9]+(st|nd|rd|th)-draft$"))] | map({name: ., num: (capture("^(?<num>[0-9]+)") | .num | tonumber)}) | sort_by(.num) | reverse | .[0].name' 2>/dev/null || echo "-")

        # Normalize null to "-"
        if [ "$DRAFT_BRANCH" = "null" ] || [ -z "$DRAFT_BRANCH" ]; then
            DRAFT_BRANCH="-"
        fi

        if [ "$DRAFT_BRANCH" != "-" ]; then
            echo "  ✓ Draft branch: $DRAFT_BRANCH"

            # Extract draft number from branch name (e.g., "4th-draft" -> 4)
            DRAFT_NUM=$(echo "$DRAFT_BRANCH" | grep -o '^[0-9]\+')

            # Check PR status on the PREVIOUS draft branch
            # (When PR is created, next draft branch is auto-generated, so current branch has no PR)
            if [ "$DRAFT_NUM" -gt 0 ] 2>/dev/null; then
                PREV_NUM=$((DRAFT_NUM - 1))
                # Convert number to ordinal suffix, handling teens (11-13) correctly
                LAST_TWO=$((PREV_NUM % 100))
                LAST_DIGIT=$((PREV_NUM % 10))
                if [ "$LAST_TWO" -ge 11 ] && [ "$LAST_TWO" -le 13 ]; then
                    PREV_BRANCH="${PREV_NUM}th-draft"
                else
                    case $LAST_DIGIT in
                        1) PREV_BRANCH="${PREV_NUM}st-draft" ;;
                        2) PREV_BRANCH="${PREV_NUM}nd-draft" ;;
                        3) PREV_BRANCH="${PREV_NUM}rd-draft" ;;
                        *) PREV_BRANCH="${PREV_NUM}th-draft" ;;
                    esac
                fi

                PR_STATE=$(gh pr list --repo "smkwlab/$REPO" --head "$PREV_BRANCH" --json state --jq '.[0].state' 2>/dev/null || echo "")

                if [ "$PR_STATE" = "OPEN" ]; then
                    # Check if approved
                    REVIEW_STATE=$(gh pr view --repo "smkwlab/$REPO" "$PREV_BRANCH" --json reviewDecision --jq '.reviewDecision' 2>/dev/null || echo "")

                    if [ "$REVIEW_STATE" = "APPROVED" ]; then
                        PR_STATUS="✅ 承認済み"
                    else
                        PR_STATUS="🔍 Review中"
                    fi
                elif [ "$PR_STATE" = "MERGED" ]; then
                    PR_STATUS="✅ 承認済み"
                fi
                # Note: If the previous draft branch has a CLOSED PR or no PR at all,
                # PR_STATUS intentionally remains the default "📝 作成中" to reflect
                # that there is no active or merged PR on the previous draft.
                echo "  ✓ PR status: $PR_STATUS (checked $PREV_BRANCH)"
            else
                # 0th-draft: no previous branch to check
                echo "  ✓ PR status: $PR_STATUS (initial draft)"
            fi

            # Get index.html from draft branch
            HTML_CONTENT=$(gh api "repos/smkwlab/$REPO/contents/index.html?ref=$DRAFT_BRANCH" 2>/dev/null || echo "")
        else
            # Fallback to main branch if no draft branch exists
            HTML_CONTENT=$(gh api "repos/smkwlab/$REPO/contents/index.html" 2>/dev/null || echo "")
        fi

        # Extract file size
        HTML_SIZE=$(echo "$HTML_CONTENT" | jq -r '.size' 2>/dev/null || echo "0")
        if [ "$HTML_SIZE" != "0" ] && [ "$HTML_SIZE" != "null" ] && [ -n "$HTML_SIZE" ]; then
            FILE_SIZE="$HTML_SIZE"
            echo "  ✓ HTML file size: ${FILE_SIZE} bytes"
        else
            echo "  ✗ Could not get HTML file size"
        fi

        # Get last commit date
        if [ "$DRAFT_BRANCH" != "-" ]; then
            LAST_COMMIT=$(gh api "repos/smkwlab/$REPO/commits/$DRAFT_BRANCH" --jq '.commit.committer.date' 2>/dev/null || echo "")
        else
            LAST_COMMIT=$(gh api "repos/smkwlab/$REPO/commits/main" --jq '.commit.committer.date' 2>/dev/null || echo "")
        fi

        if [ -n "$LAST_COMMIT" ] && [ "$LAST_COMMIT" != "null" ]; then
            # Convert to MM/DD HH:MM:SS format in JST
            if date -j &>/dev/null; then
                # macOS
                LAST_COMMIT_CLEAN=$(echo "$LAST_COMMIT" | sed 's/\.[0-9]*Z$/Z/')
                LAST_UPDATE=$(TZ='Asia/Tokyo' date -j -f "%Y-%m-%dT%H:%M:%SZ" "$LAST_COMMIT_CLEAN" "+%m/%d %H:%M:%S" 2>/dev/null || echo "-")
            else
                # Linux
                LAST_UPDATE=$(TZ='Asia/Tokyo' date -d "$LAST_COMMIT" "+%m/%d %H:%M:%S" 2>/dev/null || echo "-")
            fi
            if [ "$LAST_UPDATE" != "-" ]; then
                echo "  ✓ Last update: $LAST_UPDATE"
            fi
        fi
    fi

    # Get previous day's data for comparison
    PREV_DATA=$(TZ='Asia/Tokyo' python3 scripts/extract-previous-data.py "$STUDENT_ID" 2>/dev/null || echo "{}")
    PREV_FILE_SIZE=$(echo "$PREV_DATA" | jq -r '.file_size // "-"')

    # Calculate difference
    SIZE_DIFF="-"
    if [ "$FILE_SIZE" != "-" ] && [ "$PREV_FILE_SIZE" != "-" ] && [ "$PREV_FILE_SIZE" != "null" ]; then
        DIFF=$((FILE_SIZE - PREV_FILE_SIZE))
        if [ "$DIFF" -gt 0 ]; then
            SIZE_DIFF="+${DIFF}"
        elif [ "$DIFF" -lt 0 ]; then
            SIZE_DIFF="${DIFF}"
        else
            SIZE_DIFF="±0"
        fi
        echo "  ✓ Size diff: $SIZE_DIFF (from ${PREV_FILE_SIZE} to ${FILE_SIZE} bytes)"
    fi

    # Add to output JSON
    ENTRY=$(jq -n \
        --arg student_id "$STUDENT_ID" \
        --arg name "$NAME" \
        --arg file_size "$FILE_SIZE" \
        --arg last_update "$LAST_UPDATE" \
        --arg draft_branch "$DRAFT_BRANCH" \
        --arg pr_status "$PR_STATUS" \
        --arg size_diff "$SIZE_DIFF" \
        --arg repo_exists "$REPO_EXISTS" \
        '{
            student_id: $student_id,
            name: $name,
            file_size: $file_size,
            last_update: $last_update,
            draft_branch: $draft_branch,
            pr_status: $pr_status,
            size_diff: $size_diff,
            repo_exists: $repo_exists
        }')

    # Append to output
    cat "$OUTPUT_FILE" | jq --argjson entry "$ENTRY" '. += [$entry]' > "${OUTPUT_FILE}.tmp"
    mv "${OUTPUT_FILE}.tmp" "$OUTPUT_FILE"

    echo ""
done

# Generate CSV file for data analysis
CSV_DATE=$(TZ='Asia/Tokyo' date '+%Y-%m-%d')
CSV_DIR="archive/data"
CSV_OUTPUT="${CSV_DIR}/${CSV_DATE}.csv"

mkdir -p "$CSV_DIR"

echo "Generating CSV: $CSV_OUTPUT"

# Create CSV header and data
echo "student_id,name,file_size,draft_branch,last_update" > "$CSV_OUTPUT"

# Convert JSON to CSV
cat "$OUTPUT_FILE" | jq -r '.[] | [
    .student_id,
    .name,
    (.file_size | if . == "-" then "" else . end),
    .draft_branch,
    .last_update
] | @csv' >> "$CSV_OUTPUT"

echo "  ✓ CSV saved: $CSV_OUTPUT"

echo "=== Data Collection Complete ==="
echo "Output: $OUTPUT_FILE"
echo "CSV: $CSV_OUTPUT"
echo "Total entries: $(cat "$OUTPUT_FILE" | jq 'length')"
