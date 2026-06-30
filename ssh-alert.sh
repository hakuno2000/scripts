#!/bin/bash
# Add this script by adding `session optional pam_exec.so seteuid /usr/local/bin/ssh-alert.sh` to the end of /etc/pam.d/sshd
WEBHOOK_URL=""

# Let's capture only open_session and close_session events (login and logout).
case "$PAM_TYPE" in
    open_session)
        # Extract the login method from auth logs for this specific user and IP
        # It will look for "publickey", "password", etc.
        AUTH_METHOD=$(tac /var/log/auth.log /var/log/secure 2>/dev/null | grep -i "accepted" | grep -m 1 "$PAM_USER" | grep -m 1 "$PAM_RHOST" | grep -oE '(publickey|password|keyboard-interactive)')
        SSH_CLIENT_IP=$(echo $SSH_CONNECTION | awk '{print $1}')
        LOCATION_INFO=$(curl -s "https://ipinfo.io/{$SSH_CLIENT_IP}")
        CITY=$(echo $LOCATION_INFO | jq -r '.city')
        COUNTRY=$(echo $LOCATION_INFO | jq -r '.country')

        # Fallback if the method couldn't be parsed
        if [ -z "$AUTH_METHOD" ]; then
            AUTH_METHOD="unknown"
        fi

        PAYLOAD=" { \"content\": \"🔒 **$PAM_USER** from $SSH_CLIENT_IP ($CITY, $COUNTRY) logged in **$HOSTNAME** using **$AUTH_METHOD** (remote host: $PAM_RHOST)\" }"
        ;;
    close_session)
        PAYLOAD=" { \"content\": \"🚪 **$PAM_USER** logged out **$HOSTNAME** (remote host: $PAM_RHOST)\" }"
        ;;
esac

# Let's only perform a request if there is an actual payload to send.
if [ -n "$PAYLOAD" ] ; then
    curl -X POST -H 'Content-Type: application/json' -d "$PAYLOAD" "$WEBHOOK_URL"
fi
