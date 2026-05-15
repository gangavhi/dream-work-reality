#!/usr/bin/env bash
# Deploy static privacy policy to S3 with website hosting enabled.
# HTTPS for App Store: use the printed "HTTPS object URL" (S3 REST), not the website endpoint (HTTP only).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
INDEX_HTML="${SCRIPT_DIR}/index.html"

: "${BUCKET_NAME:?Set BUCKET_NAME to a globally unique bucket name (e.g. dreamwork-privacy-policy-prod)}"
: "${AWS_REGION:=us-east-1}"

if ! command -v aws >/dev/null 2>&1; then
  echo "aws CLI not found. Install AWS CLI v2 and configure credentials." >&2
  exit 1
fi

SUPPORT_HTML="${SCRIPT_DIR}/support/index.html"

if [[ ! -f "${INDEX_HTML}" ]]; then
  echo "Missing ${INDEX_HTML}" >&2
  exit 1
fi
if [[ ! -f "${SUPPORT_HTML}" ]]; then
  echo "Missing ${SUPPORT_HTML}" >&2
  exit 1
fi

if aws s3api head-bucket --bucket "${BUCKET_NAME}" 2>/dev/null; then
  echo "Bucket ${BUCKET_NAME} already exists."
else
  echo "Creating bucket ${BUCKET_NAME} in ${AWS_REGION}..."
  if [[ "${AWS_REGION}" == "us-east-1" ]]; then
    aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}"
  else
    aws s3api create-bucket --bucket "${BUCKET_NAME}" --region "${AWS_REGION}" \
      --create-bucket-configuration LocationConstraint="${AWS_REGION}"
  fi
fi

echo "Allowing public read via bucket policy (required for anonymous HTTPS GET to objects)..."
aws s3api put-public-access-block --bucket "${BUCKET_NAME}" \
  --public-access-block-configuration \
  'BlockPublicAcls=false,IgnorePublicAcls=false,BlockPublicPolicy=false,RestrictPublicBuckets=false'

POLICY="$(cat <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "AllowPublicReadPrivacyPolicy",
      "Effect": "Allow",
      "Principal": "*",
      "Action": "s3:GetObject",
      "Resource": "arn:aws:s3:::${BUCKET_NAME}/*"
    }
  ]
}
EOF
)"

aws s3api put-bucket-policy --bucket "${BUCKET_NAME}" --policy "${POLICY}"

echo "Enabling static website hosting (index.html) — website endpoint is HTTP-only..."
aws s3api put-bucket-website --bucket "${BUCKET_NAME}" \
  --website-configuration '{"IndexDocument":{"Suffix":"index.html"},"ErrorDocument":{"Key":"index.html"}}'

echo "Uploading index.html..."
aws s3 cp "${INDEX_HTML}" "s3://${BUCKET_NAME}/index.html" \
  --region "${AWS_REGION}" \
  --content-type "text/html; charset=utf-8" \
  --cache-control "max-age=3600"

echo "Uploading support/index.html..."
aws s3 cp "${SUPPORT_HTML}" "s3://${BUCKET_NAME}/support/index.html" \
  --region "${AWS_REGION}" \
  --content-type "text/html; charset=utf-8" \
  --cache-control "max-age=3600"

WEBSITE_HOST="${BUCKET_NAME}.s3-website-${AWS_REGION}.amazonaws.com"
HTTPS_PRIVACY_URL="https://${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com/index.html"
HTTPS_SUPPORT_URL="https://${BUCKET_NAME}.s3.${AWS_REGION}.amazonaws.com/support/index.html"

echo ""
echo "Done."
echo "  Website (HTTP only):  http://${WEBSITE_HOST}/"
echo "  Privacy (HTTPS):      ${HTTPS_PRIVACY_URL}"
echo "  Support (HTTPS):      ${HTTPS_SUPPORT_URL}"
echo ""
echo "App Store Connect: Privacy Policy URL → ${HTTPS_PRIVACY_URL}"
echo "App Store Connect: Support URL        → ${HTTPS_SUPPORT_URL}"
echo "Google Play:       Privacy policy URL → ${HTTPS_PRIVACY_URL}"
echo "Google Play:       Support / contact  → ${HTTPS_SUPPORT_URL}"
echo ""
echo "After you edit HTML, re-run: AWS_REGION=${AWS_REGION} BUCKET_NAME=${BUCKET_NAME} ${SCRIPT_DIR}/deploy.sh"
