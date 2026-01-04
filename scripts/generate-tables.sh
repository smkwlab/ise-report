#!/bin/bash
set -e

# Generate progress tables for ISE reports
# Input: progress-data.json, archive/data/*.csv
# Output: README.md

export TZ='Asia/Tokyo'

INPUT_FILE="progress-data.json"
OUTPUT_FILE="README.md"

echo "=== Generating Progress Tables ==="
echo ""

# Get current date in JST
CURRENT_DATETIME=$(date '+%Y-%m-%d %H:%M %Z')
CURRENT_DATE=$(date '+%Y-%m-%d')

# Start generating README
cat > "$OUTPUT_FILE" << 'EOF'
# ISE Report Progress

2024年度 情報科学演習II レポート 進捗状況ダッシュボード

EOF

echo "**最終更新**: $CURRENT_DATETIME (自動更新)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Generate progress table
cat >> "$OUTPUT_FILE" << 'EOF'
## 📊 進捗状況一覧

| 学籍番号 | 著者 | サイズ | Δサイズ | 最終更新 | ドラフト | 状態 |
|---------|------|-------:|--------:|------------------|---------|------|
EOF

# Sort by file size (descending) and generate table rows
jq -r 'sort_by(-(if .file_size == "-" then 0 else (.file_size | tonumber) end)) | .[] | [
    .student_id,
    .name,
    .file_size,
    .size_diff,
    .last_update,
    .draft_branch,
    .pr_status,
    .repo_exists
] | @tsv' "$INPUT_FILE" | while IFS=$'\t' read -r STUDENT_ID NAME FILE_SIZE SIZE_DIFF LAST_UPDATE DRAFT_BRANCH PR_STATUS REPO_EXISTS; do
    # Skip if repo doesn't exist
    if [ "$REPO_EXISTS" = "false" ]; then
        echo "| $STUDENT_ID | $NAME | - | - | - | - | ⏳ 未作成 |" >> "$OUTPUT_FILE"
        continue
    fi

    # Format student ID link
    REPO="${STUDENT_ID}-ise-report2"
    if [ "$DRAFT_BRANCH" != "-" ]; then
        STUDENT_LINK="[${STUDENT_ID}](https://github.com/smkwlab/${REPO}/tree/${DRAFT_BRANCH})"
    else
        STUDENT_LINK="[${STUDENT_ID}](https://github.com/smkwlab/${REPO})"
    fi

    # Format file size with link
    if [ "$FILE_SIZE" != "-" ]; then
        if [ "$DRAFT_BRANCH" != "-" ]; then
            SIZE_LINK="[${FILE_SIZE} bytes](https://github.com/smkwlab/${REPO}/blob/${DRAFT_BRANCH}/index.html)"
        else
            SIZE_LINK="[${FILE_SIZE} bytes](https://github.com/smkwlab/${REPO}/blob/main/index.html)"
        fi
    else
        SIZE_LINK="-"
    fi

    echo "| $STUDENT_LINK | $NAME | $SIZE_LINK | $SIZE_DIFF | $LAST_UPDATE | $DRAFT_BRANCH | $PR_STATUS |" >> "$OUTPUT_FILE"
done

# Add notes and schedule sections
cat >> "$OUTPUT_FILE" << 'EOF'

> **注**: この表は GitHub Actions により毎日自動更新されます。

## 📅 重要日程

- **レポート提出期限**: 各回の締切参照

## 📈 統計情報

EOF

# Calculate statistics
TOTAL=$(jq 'length' "$INPUT_FILE")
EXISTING=$(jq '[.[] | select(.repo_exists == "true")] | length' "$INPUT_FILE")
WITH_PR=$(jq '[.[] | select(.pr_status | test("Review|承認"))] | length' "$INPUT_FILE")
APPROVED=$(jq '[.[] | select(.pr_status | test("承認"))] | length' "$INPUT_FILE")

cat >> "$OUTPUT_FILE" << EOF
- **登録学生数**: $TOTAL 名
- **リポジトリ作成済み**: $EXISTING 名
- **PR提出済み**: $WITH_PR 名
- **承認済み**: $APPROVED 名

## 📉 進捗グラフ

### 💾 学生別ファイルサイズ推移

EOF

# Generate line chart from CSV data
CHART_DATA_DIR="archive/data"
CHART_IMAGE=""

if [ -d "$CHART_DATA_DIR" ]; then
    CSV_FILES=$(ls "$CHART_DATA_DIR"/*.csv 2>/dev/null | sort)

    if [ -n "$CSV_FILES" ]; then
        # Get dates for x-axis labels
        LABELS=""
        for csv_file in $CSV_FILES; do
            filename=$(basename "$csv_file" .csv)
            date_label=$(echo "$filename" | sed 's/^[0-9]\{4\}-//' | sed 's/-/\//')
            if [ -n "$LABELS" ]; then
                LABELS="$LABELS,'$date_label'"
            else
                LABELS="'$date_label'"
            fi
        done

        # Get latest CSV for sorting students by file size
        LATEST_CSV=$(ls "$CHART_DATA_DIR"/*.csv 2>/dev/null | sort | tail -1)
        STUDENT_IDS=$(tail -n +2 "$LATEST_CSV" | awk -F',' '{gsub(/"/, "", $1); gsub(/"/, "", $3); if($3 != "") print $3 " " $1}' | sort -rn | awk '{print $2}')

        if [ -n "$STUDENT_IDS" ]; then
            # Build datasets for file size chart
            DATASETS=""
            for student_id in $STUDENT_IDS; do
                author=$(tail -n +2 "$LATEST_CSV" | awk -F',' -v id="$student_id" '{gsub(/"/, "", $1); gsub(/"/, "", $2); if($1==id) print $2}')
                STUDENT_SIZE_DATA=""
                for csv_file in $CSV_FILES; do
                    size=$(tail -n +2 "$csv_file" | awk -F',' -v id="$student_id" '{gsub(/"/, "", $1); gsub(/"/, "", $3); if($1==id && $3 != "") printf "%.1f", $3/1024}')
                    if [ -z "$size" ]; then size="0.0"; fi
                    if [ -n "$STUDENT_SIZE_DATA" ]; then
                        STUDENT_SIZE_DATA="$STUDENT_SIZE_DATA,$size"
                    else
                        STUDENT_SIZE_DATA="$size"
                    fi
                done
                author_escaped=$(printf '%s' "$author" | jq -Rs .)
                if [ -n "$DATASETS" ]; then DATASETS="$DATASETS,"; fi
                DATASETS="${DATASETS}{label:$author_escaped,data:[$STUDENT_SIZE_DATA],fill:false}"
            done

            CHART_CONFIG="{type:'line',data:{labels:[$LABELS],datasets:[$DATASETS]},options:{title:{display:true,text:'学生別ファイルサイズ推移 (KB)'},legend:{position:'right'},scales:{yAxes:[{ticks:{beginAtZero:true}}]}}}"
            ENCODED_CONFIG=$(printf '%s' "$CHART_CONFIG" | python3 -c 'import urllib.parse,sys; print(urllib.parse.quote(sys.stdin.read()))')
            QUICKCHART_URL="https://quickchart.io/chart?c=$ENCODED_CONFIG&w=500&h=400"

            # Create charts directory and save chart image
            mkdir -p charts
            echo "Downloading file size chart image..."
            CHART_IMAGE="charts/${CURRENT_DATE}-file-size.png"
            if curl -s -o "$CHART_IMAGE" "$QUICKCHART_URL"; then
                echo "  Saved to $CHART_IMAGE"
            else
                echo "  Warning: Failed to download chart"
                rm -f "$CHART_IMAGE"
                CHART_IMAGE=""
            fi
        fi
    fi
fi

if [ -n "$CHART_IMAGE" ]; then
    echo "![学生別ファイルサイズ推移]($CHART_IMAGE)" >> "$OUTPUT_FILE"
else
    echo "グラフデータが見つかりませんでした。" >> "$OUTPUT_FILE"
fi

cat >> "$OUTPUT_FILE" << 'EOF'

## 📖 年度別レポート

- [2024年度](2024/) (現在)

## 🔄 更新履歴

過去のスナップショットは [archive/snapshots/](archive/snapshots/) に保存されています。
EOF

echo ""
echo "=== Table Generation Complete ==="
echo "Output: $OUTPUT_FILE"
