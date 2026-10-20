#!/bin/sh
# Restore real visitor IPs behind Cloudflare for the whole DSM nginx (websites, DSM login via a reverse
# proxy, Photo Station ...), so DSM Auto Block and logs see real IPs instead of Cloudflare's.
#
# DSM 6.2's nginx.conf already contains, at http level:
#   real_ip_header X-Forwarded-For; real_ip_recursive on; set_real_ip_from 127.0.0.1;
#   include /var/tmp/nginx/trusted_proxy/*.conf;
# DSM 6.2 has no UI that fills that folder, so this script writes it. /var/tmp can be cleared,
# so run "ensure" from DSM Task Scheduler (root, every 10 minutes) to put it back.
#
#   sh realip.sh apply    write the file, test nginx, reload (removes it again if the test fails)
#   sh realip.sh ensure   same, but only when the file is missing or different
#   sh realip.sh refresh  download the current Cloudflare ranges into cloudflare-ranges.txt, then apply
#   sh realip.sh remove   delete the file and reload (undo)
#   sh realip.sh status   show whether it is in place
set -u

# ---- settings ------------------------------------------------------------------------------
# Your NAS's own LAN IP. Needed when DSM's reverse proxy forwards to https://<NAS-IP>:<DSM port>,
# because that second hop comes from the NAS itself. Leave empty if you don't use the reverse proxy.
NAS_IP=192.168.0.10
# --------------------------------------------------------------------------------------------

HERE=$(cd "$(dirname "$0")" && pwd)
RANGES=$HERE/cloudflare-ranges.txt
DIR=/var/tmp/nginx/trusted_proxy
CONF=$DIR/cloudflare-realip.conf
NGINX=/usr/bin/nginx
LOG=$HERE/realip.log

want() {
	echo "# Cloudflare edges (and this NAS, for the DSM reverse proxy hop) are trusted proxies."
	[ -n "$NAS_IP" ] && echo "set_real_ip_from $NAS_IP;"
	grep -E '^[0-9a-fA-F:.]+/[0-9]+$' "$RANGES" | sed 's/^/set_real_ip_from /; s/$/;/'
}

reload() {
	$NGINX -t >/dev/null 2>&1 && $NGINX -s reload
}

apply() {
	[ -s "$RANGES" ] || { echo "missing $RANGES"; return 1; }
	mkdir -p "$DIR"
	want > "$CONF.new" && mv "$CONF.new" "$CONF"
	if reload; then
		echo "$(date '+%F %T') applied" >> "$LOG"
		echo "applied: $CONF ($(grep -c set_real_ip_from "$CONF") entries)"
	else
		rm -f "$CONF"; reload
		echo "$(date '+%F %T') nginx test failed, removed" >> "$LOG"
		echo "nginx config test failed; removed the file again"
		return 1
	fi
}

refresh() {
	tmp=$(mktemp)
	if curl -fsS -m 20 https://www.cloudflare.com/ips-v4 > "$tmp" && echo >> "$tmp" && curl -fsS -m 20 https://www.cloudflare.com/ips-v6 >> "$tmp"; then
		n=$(grep -cE '^[0-9a-fA-F:.]+/[0-9]+$' "$tmp")
		if [ "$n" -ge 10 ]; then
			grep -E '^[0-9a-fA-F:.]+/[0-9]+$' "$tmp" > "$RANGES"
			echo "downloaded $n ranges"
			rm -f "$tmp"; apply; return
		fi
	fi
	rm -f "$tmp"
	echo "download failed; kept the existing list"
	return 1
}

case "${1:-status}" in
	apply)   apply ;;
	ensure)  if [ ! -f "$CONF" ] || [ "$(want)" != "$(cat "$CONF")" ]; then apply; fi ;;
	refresh) refresh ;;
	remove)  rm -f "$CONF"; reload; echo "$(date '+%F %T') removed" >> "$LOG"; echo "removed" ;;
	status)  if [ -f "$CONF" ]; then echo "in place ($(grep -c set_real_ip_from "$CONF") entries)"; else echo "not in place"; fi ;;
	*)       echo "usage: $0 apply|ensure|refresh|remove|status"; exit 1 ;;
esac
