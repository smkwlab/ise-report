#!/bin/bash
set -e

# Generate progress tables for ISE reports
# Input: progress-data.json
# Output: README.md

INPUT_FILE="progress-data.json"
OUTPUT_FILE="README.md"

echo "=== Generating Progress Tables ==="
echo ""

# Get current date in JST
CURRENT_DATE=$(TZ='Asia/Tokyo' date '+%Y-%m-%d %H:%M JST')

# Start generating README
cat > "$OUTPUT_FILE" << 'EOF'
# ISE Report Progress

2024年度 情報科学演習II レポート 進捗状況ダッシュボード

EOF

echo "**最終更新**: $CURRENT_DATE (自動更新)" >> "$OUTPUT_FILE"
echo "" >> "$OUTPUT_FILE"

# Generate progress table
cat >> "$OUTPUT_FILE" << 'EOF'
## 📊 進捗状況一覧

| 学籍番号 | 著者 | サイズ | Δサイズ | 最終更新 | ドラフト | 状態 |
|---------|------|-------:|--------:|------------------|---------|------|
EOF

# Sort by file size (descending) and generate table rows
jq -r 'sort_by(-.file_size | if . == "-" then 0 else tonumber end) | .[] | [
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

### 💾 学生別ファイルサイズ

EOF

# Generate chart URL for file sizes
CHART_DATA=$(jq -r '[.[] | select(.file_size != "-" and .repo_exists == "true")] | sort_by(-.file_size | tonumber) | .[0:12] |
    "labels:" + ([.[].name] | @json) + ",data:" + ([.[].file_size | tonumber / 1000 | . * 10 | floor / 10] | @json)' "$INPUT_FILE" 2>/dev/null || echo "labels:[],data:[]")

if [ -n "$CHART_DATA" ] && [ "$CHART_DATA" != "labels:[],data:[]" ]; then
    LABELS=$(echo "$CHART_DATA" | sed 's/,data:.*//' | sed 's/labels://')
    DATA=$(echo "$CHART_DATA" | sed 's/.*data://')

    CHART_URL="https://quickchart.io/chart?c={type:'bar',data:{labels:${LABELS},datasets:[{label:'ファイルサイズ(KB)',data:${DATA},backgroundColor:'rgba(54,162,235,0.6)'}]},options:{title:{display:true,text:'学生別ファイルサイズ'},scales:{yAxes:[{ticks:{beginAtZero:true}}]}}}&w=600&h=400"

    # URL encode
    CHART_URL=$(echo "$CHART_URL" | sed "s/'/%27/g" | sed 's/ /%20/g')

    echo "![学生別ファイルサイズ]($CHART_URL)" >> "$OUTPUT_FILE"
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
