#!/usr/bin/env bash
#
# Peggo orchestrator health check with Slack notifications.
#
# Usage:
#   SLACK_WEBHOOK_URL="https://hooks.slack.com/services/T000/B000/XXXX" \
#     ./peggo.sh <your_orchestrator_inj_address>
#
# Environment variables:
#   SLACK_WEBHOOK_URL  Slack incoming webhook URL. If unset, the script only prints
#                      to stdout and does not notify.
#   NOTIFY_ALWAYS      "true" to post to Slack even when everything is healthy.
#                      Default "false" (only posts when something is wrong).
#   VALIDATOR_NAME     Friendly label used in the Slack message.
#                      Default: the orchestrator address.
#   INJECTIVE_LCD_URL  LCD endpoint. Default: https://sentry.lcd.injective.network
#   CURL_TIMEOUT       Per-request timeout in seconds. Default: 15
#
# Exit code: 0 if all checks pass, 1 if any check fails or errors.

set -uo pipefail

# --------------------------------------------------------------------------
# Dependencies
# --------------------------------------------------------------------------
if ! command -v jq &> /dev/null
then
    echo "⚠️ jq command could not be found!"
    echo "jq is a lightweight and flexible command-line JSON processor."
    echo "Install it by checking https://stedolan.github.io/jq/download/"
    exit 1
fi

if ! command -v curl &> /dev/null
then
    echo "⚠️ curl command could not be found!"
    exit 1
fi

# --------------------------------------------------------------------------
# Arguments / configuration
# --------------------------------------------------------------------------
if [ -z "${1:-}" ]
  then
    echo "Run the script with valid orchestrator inj address as argument"
    exit 1
fi

YOUR_ORCHESTRATOR_INJ_ADDRESS="$1"
INJECTIVE_LCD_URL="${INJECTIVE_LCD_URL:-https://sentry.lcd.injective.network}"
SLACK_WEBHOOK_URL="${SLACK_WEBHOOK_URL:-}"
NOTIFY_ALWAYS="${NOTIFY_ALWAYS:-false}"
VALIDATOR_NAME="${VALIDATOR_NAME:-$YOUR_ORCHESTRATOR_INJ_ADDRESS}"
CURL_TIMEOUT="${CURL_TIMEOUT:-15}"

FAILURES=0
REPORT=""

# Append one line to the Slack message body.
add_line() {
    REPORT+="$1"$'\n'
}

# Mark a failed check.
fail() {
    FAILURES=$((FAILURES + 1))
}

# Fetch a URL, print body on success, empty on failure.
fetch() {
    curl -s --max-time "${CURL_TIMEOUT}" "$1"
}

# --------------------------------------------------------------------------
# Slack
# --------------------------------------------------------------------------
send_slack() {
    local color="$1" title="$2" body="$3"

    if [ -z "${SLACK_WEBHOOK_URL}" ]; then
        echo ""
        echo "SLACK_WEBHOOK_URL is not set - skipping Slack notification."
        return 0
    fi

    local payload http_code
    payload=$(jq -n \
        --arg color "${color}" \
        --arg title "${title}" \
        --arg body "${body}" \
        --arg footer "$(date -u '+%Y-%m-%d %H:%M:%S UTC') • \`${VALIDATOR_NAME}\`" \
        '{
            text: $title,
            attachments: [
                {
                    color: $color,
                    blocks: [
                        { type: "header",
                          text: { type: "plain_text", text: $title, emoji: true } },
                        { type: "section",
                          text: { type: "mrkdwn", text: $body } },
                        { type: "context",
                          elements: [ { type: "mrkdwn", text: $footer } ] }
                    ]
                }
            ]
        }')

    http_code=$(curl -s -o /dev/null -w '%{http_code}' \
        --max-time "${CURL_TIMEOUT}" \
        -X POST \
        -H 'Content-Type: application/json' \
        --data "${payload}" \
        "${SLACK_WEBHOOK_URL}")

    echo ""
    if [ "${http_code}" = "200" ]; then
        echo "Slack notification sent."
    else
        echo "Slack notification failed (HTTP ${http_code})."
    fi
}

# --------------------------------------------------------------------------
# 1. Pending batches
# --------------------------------------------------------------------------
echo "1. Check pending batches to be confirmed"
echo "SLASHING_CONDITION - You will be slashed if a batch request is not confirmed within 25000 blocks upon creation."

batch=$(fetch "${INJECTIVE_LCD_URL}/peggy/v1/batch/last?address=${YOUR_ORCHESTRATOR_INJ_ADDRESS}")
result=$(echo "${batch}" | jq -r '.batch | length' 2>/dev/null)

if ! [[ "${result}" =~ ^[0-9]+$ ]]; then
    echo "(X) could not query pending batches from ${INJECTIVE_LCD_URL}"
    add_line ":warning: *Pending batches* — LCD query failed"
    fail
elif [ "${result}" -eq 0 ]; then
    echo "(O) No pending batches"
    add_line ":white_check_mark: *Pending batches* — none"
else
    echo "(X) result :"
    echo "${batch}"
    add_line ":x: *Pending batches* — ${result} unconfirmed (slashable after 25000 blocks)"
    fail
fi

# --------------------------------------------------------------------------
# 2. Pending valsets
# --------------------------------------------------------------------------
echo ""
echo "2. Check pending valsets to be confirmed"
echo "SLASHING_CONDITION - You will be slashed if a valset request is not confirmed within 25000 blocks upon creation."

valsets=$(fetch "${INJECTIVE_LCD_URL}/peggy/v1/valset/last?address=${YOUR_ORCHESTRATOR_INJ_ADDRESS}")
result=$(echo "${valsets}" | jq -r '.valsets | length' 2>/dev/null)

if ! [[ "${result}" =~ ^[0-9]+$ ]]; then
    echo "(X) could not query pending valsets from ${INJECTIVE_LCD_URL}"
    add_line ":warning: *Pending valsets* — LCD query failed"
    fail
elif [ "${result}" -eq 0 ]; then
    echo "(O) No Pending Valsets"
    add_line ":white_check_mark: *Pending valsets* — none"
else
    echo "(X) result : "
    echo "${valsets}"
    add_line ":x: *Pending valsets* — ${result} unconfirmed (slashable after 25000 blocks)"
    fail
fi

# --------------------------------------------------------------------------
# 3. Last broadcasted event freshness
# --------------------------------------------------------------------------
echo ""
echo "3. Check latest event broadcasted by peggo is upto date"
echo "SLASHING_CONDITION - You will be slashed if you don't broadcast an event within 25000 blocks and it's broadcasted by majority of validators. This is disabled for now."

lon=$(fetch "${INJECTIVE_LCD_URL}/peggy/v1/module_state" \
        | jq -r '.state.last_observed_nonce // empty' 2>/dev/null)
lce=$(fetch "${INJECTIVE_LCD_URL}/peggy/v1/oracle/event/${YOUR_ORCHESTRATOR_INJ_ADDRESS}" \
        | jq -r '.last_claim_event.ethereum_event_nonce // empty' 2>/dev/null)

if [ -z "${lon}" ] || [ -z "${lce}" ]; then
    echo "(X) could not read nonces (last_observed_nonce:'${lon}' last_claim_event:'${lce}')"
    add_line ":warning: *Event nonce* — LCD query failed"
    fail
elif [ "${lon}" = "${lce}" ]; then
    echo "(O) your peggo is upto date"
    add_line ":white_check_mark: *Event nonce* — up to date (\`${lon}\`)"
else
    echo "(X) check peggo last_observed_nonce:${lon}, last_claim_event.ethereum_event_nonce:${lce}"
    if [[ "${lon}" =~ ^[0-9]+$ ]] && [[ "${lce}" =~ ^[0-9]+$ ]]; then
        add_line ":x: *Event nonce* — behind by $((lon - lce)) (observed \`${lon}\`, claimed \`${lce}\`)"
    else
        add_line ":x: *Event nonce* — mismatch (observed \`${lon}\`, claimed \`${lce}\`)"
    fi
    fail
fi

# --------------------------------------------------------------------------
# Notify
# --------------------------------------------------------------------------
if [ "${FAILURES}" -gt 0 ]; then
    send_slack "danger" \
        ":rotating_light: Peggo check failed (${FAILURES})" \
        "${REPORT}"
    exit 1
fi

if [ "${NOTIFY_ALWAYS}" = "true" ]; then
    send_slack "good" \
        ":white_check_mark: Peggo healthy" \
        "${REPORT}"
fi

exit 0
