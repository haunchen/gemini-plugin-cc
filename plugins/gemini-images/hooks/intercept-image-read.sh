#!/bin/bash
# Intercept Claude Read tool calls for image files.
# Convert the image into a short text description before it enters the main session.

set -euo pipefail

INPUT=$(cat)
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty')

if [ -z "$FILE_PATH" ] || [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

case "${FILE_PATH##*.}" in
  png|jpg|jpeg|gif|webp|avif|bmp|tiff|tif|PNG|JPG|JPEG|GIF|WEBP|AVIF|BMP|TIFF|TIF)
    ;;
  *)
    exit 0
    ;;
esac

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
TMP_DIR="${TMPDIR:-/tmp}"
TIMESTAMP=$(date +%s)
MAX_WIDTH="${MAX_WIDTH:-1568}"
OCR_BIN="${OCR_BIN:-tesseract}"

DESC_FILE=$(mktemp "${TMP_DIR%/}/claude-image-desc-${TIMESTAMP}-XXXXXX")
WORK_FILE="$FILE_PATH"
RESIZED_FILE="$WORK_FILE"
OCR_FILE=$(mktemp "${TMP_DIR%/}/claude-image-ocr-${TIMESTAMP}-XXXXXX")
GEMINI_FILE=$(mktemp "${TMP_DIR%/}/claude-image-gemini-${TIMESTAMP}-XXXXXX")

cleanup() {
  rm -f "$OCR_FILE" "$GEMINI_FILE" 2>/dev/null || true
  if [ "$RESIZED_FILE" != "$WORK_FILE" ]; then
    rm -f "$RESIZED_FILE" 2>/dev/null || true
  fi
  if [ "$WORK_FILE" != "$FILE_PATH" ]; then
    rm -f "$WORK_FILE" 2>/dev/null || true
  fi
}
trap cleanup EXIT

convert_if_needed() {
  case "${FILE_PATH##*.}" in
    avif|AVIF|bmp|BMP|tiff|tif|TIFF|TIF)
      local converted
      converted=$(mktemp "${TMP_DIR%/}/claude-image-convert-${TIMESTAMP}-XXXXXX")
      mv "$converted" "${converted}.jpg"
      converted="${converted}.jpg"
      if command -v magick >/dev/null 2>&1; then
        if magick "$FILE_PATH" "$converted" >/dev/null 2>&1; then
          WORK_FILE="$converted"
          return 0
        fi
      fi
      if command -v sips >/dev/null 2>&1; then
        if sips -s format jpeg "$FILE_PATH" --out "$converted" >/dev/null 2>&1; then
          WORK_FILE="$converted"
          return 0
        fi
      fi
      rm -f "$converted" >/dev/null 2>&1 || true
      ;;
  esac
}

resize_if_needed() {
  local resized
  resized=$(mktemp "${TMP_DIR%/}/claude-image-resize-${TIMESTAMP}-XXXXXX")
  mv "$resized" "${resized}.jpg"
  resized="${resized}.jpg"

  if command -v magick >/dev/null 2>&1; then
    local width
    width=$(magick identify -format '%w' "$WORK_FILE" 2>/dev/null || echo "")
    if [ -z "$width" ] || [ "$width" -le "$MAX_WIDTH" ] 2>/dev/null; then
      rm -f "$resized" >/dev/null 2>&1 || true
      return 0
    fi
    if magick "$WORK_FILE" -resize "${MAX_WIDTH}x>" -quality 80 "$resized" >/dev/null 2>&1; then
      RESIZED_FILE="$resized"
      return 0
    fi
    rm -f "$resized" >/dev/null 2>&1 || true
    return 0
  fi

  if command -v sips >/dev/null 2>&1; then
    local width
    width=$(sips -g pixelWidth "$WORK_FILE" 2>/dev/null | awk '/pixelWidth/ {print $2}')
    if [ -z "$width" ] || [ "$width" -le "$MAX_WIDTH" ] 2>/dev/null; then
      rm -f "$resized" >/dev/null 2>&1 || true
      return 0
    fi
    if sips --resampleWidth "$MAX_WIDTH" -s format jpeg -s formatOptions 80 "$WORK_FILE" --out "$resized" >/dev/null 2>&1; then
      RESIZED_FILE="$resized"
      return 0
    fi
    rm -f "$resized" >/dev/null 2>&1 || true
    return 0
  fi

  rm -f "$resized" >/dev/null 2>&1 || true
}

run_ocr() {
  if [ "$OCR_BIN" = "none" ] || [ -z "$OCR_BIN" ]; then
    return 0
  fi

  if ! command -v "$OCR_BIN" >/dev/null 2>&1; then
    return 0
  fi

  "$OCR_BIN" "$RESIZED_FILE" stdout 2>/dev/null || true
}

convert_if_needed
resize_if_needed

run_ocr > "$OCR_FILE" &
OCR_PID=$!

node "$SCRIPT_DIR/image-describe.mjs" "$RESIZED_FILE" > "$GEMINI_FILE" 2>/dev/null &
GEMINI_PID=$!

wait "$OCR_PID" 2>/dev/null || true
wait "$GEMINI_PID" 2>/dev/null || true

GEMINI_DESC=$(cat "$GEMINI_FILE" 2>/dev/null || true)
OCR_TEXT=$(cat "$OCR_FILE" 2>/dev/null || true)

if [ -z "$GEMINI_DESC" ] && [ -z "$OCR_TEXT" ]; then
  echo "[gemini-images] Both Gemini and OCR failed for $FILE_PATH; letting Claude read the original image." >&2
  rm -f "$DESC_FILE" >/dev/null 2>&1 || true
  exit 0
fi

{
  echo "[Image: $(basename "$FILE_PATH")]"
  echo
  if [ -n "$GEMINI_DESC" ]; then
    echo "$GEMINI_DESC"
  fi
  if [ -n "$OCR_TEXT" ]; then
    echo
    if [ -n "$GEMINI_DESC" ]; then
      echo "[OCR Supplement]"
    else
      echo "[OCR Text]"
    fi
    echo "$OCR_TEXT"
  fi
} > "$DESC_FILE"

jq -n --arg path "$DESC_FILE" '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    updatedInput: { file_path: $path },
    additionalContext: "The image was converted into a text description before entering the main session to reduce Claude cache churn."
  }
}'
