#!/bin/sh
# Run an existing WordPress site on PHP 8.3 in Docker on Synology DSM 6.2 (Web Station stops at PHP 7.4).
# DSM nginx keeps TLS and HTTP->HTTPS; only its proxy target changes:
#   Web Station Apache + PHP 7.4 (127.0.0.1:OLD_PORT)  <->  this container, Apache + PHP 8.3 (127.0.0.1:NEW_PORT)
#
# Run as root:  sudo sh wp-php8.sh <command>
#   install   copy this folder to $DIR and start the container (site is not switched yet)
#   status    container, PHP version, test response, where nginx points
#   switch    send the site to the container = PHP 8.3
#   rollback  send it back to Web Station = PHP 7.4, and keep it there until the next "switch"
#   ensure    for DSM Task Scheduler (every 10 min): re-apply "switch" after Web Station rewrites its
#             nginx file, and fall back to PHP 7.4 by itself if the container stops answering
#   update    pull the newest PHP 8.3 image (security fixes) and restart
#   reinstall copy config again and recreate the container; falls back to PHP 7.4 if it fails
#   fixowner  give files written as root back to the web user
#   up | down | logs
set -u

# ---- settings: change these for your NAS --------------------------------------------------
SITE_DOMAIN=example.com                       # your site's domain (used for the health check)
DIR=/volume1/ops/wp-php8                      # where this folder lives on the NAS (root-owned)
WP_DIR=/volume1/web/wordpress                 # the WordPress folder Web Station serves
WEB_UID=1023                                  # Web Station's web user (http): check with `id http`
VHOST=/etc/nginx/app.d/server.webstation-vhost.conf
OLD_PORT=915                                  # Web Station's Apache backend (see proxy_pass in $VHOST)
NEW_PORT=8083                                 # must match HOST_PORT in .env
CONTAINER=wp-php83
PROJECT=wp-php8
# --------------------------------------------------------------------------------------------

OLD="proxy_pass  http://127.0.0.1:$OLD_PORT;"
NEW="proxy_pass  http://127.0.0.1:$NEW_PORT;"
DOCKER=/usr/local/bin/docker
COMPOSE="/usr/local/bin/docker-compose -p $PROJECT -f $DIR/docker-compose.yml"
NGINX=/usr/bin/nginx
PIN=$DIR/rolled-back
LOG=$DIR/logs/ensure.log

say() { echo "[wp-php8] $*"; }

need_root() {
	if [ "$(id -u)" != 0 ]; then
		say "run with sudo: sudo sh $0 ${1:-}"
		exit 1
	fi
}

# Healthy = the container answers like WordPress: login page and home page both 200.
healthy() {
	login=$(curl -s -o /dev/null -w '%{http_code}' -m 15 -H "Host: $SITE_DOMAIN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$NEW_PORT/wp-login.php")
	home=$(curl -s -o /dev/null -w '%{http_code}' -m 15 -H "Host: $SITE_DOMAIN" -H 'X-Forwarded-Proto: https' "http://127.0.0.1:$NEW_PORT/")
	[ "$login" = 200 ] && [ "$home" = 200 ]
}

points_to() {
	if grep -qF "$NEW" "$VHOST"; then echo "container (PHP 8.3)"
	elif grep -qF "$OLD" "$VHOST"; then echo "webstation (PHP 7.4)"
	else echo "unknown"; fi
}

reload_nginx() {
	if $NGINX -t >/dev/null 2>&1; then
		$NGINX -s reload
		return 0
	fi
	say "nginx config test failed:"
	$NGINX -t
	return 1
}

do_switch() {
	cp -p "$VHOST" "$DIR/backup/vhost-$(date +%Y%m%d-%H%M%S).conf"
	sed -i "s|$OLD|$NEW|g" "$VHOST"
	if ! reload_nginx; then
		sed -i "s|$NEW|$OLD|g" "$VHOST"
		reload_nginx
		return 1
	fi
	return 0
}

do_rollback() {
	sed -i "s|$NEW|$OLD|g" "$VHOST"
	reload_nginx
}

wait_healthy() {
	i=0
	while [ $i -lt 30 ]; do
		healthy && return 0
		sleep 3
		i=$((i + 1))
	done
	return 1
}

install_files() {
	src=$(cd "$(dirname "$0")" && pwd)
	mkdir -p "$DIR/php" "$DIR/apache" "$DIR/backup" "$DIR/logs"
	if [ "$src" != "$DIR" ]; then
		cp "$src/docker-compose.yml" "$src/.env" "$DIR/"
		cp "$src/php/zz-custom.ini" "$DIR/php/"
		cp "$src/apache/000-default.conf" "$src/apache/remoteip.conf" "$src/apache/ports.conf" "$DIR/apache/"
		cp "$src/wp-php8.sh" "$DIR/"
	fi
	chown -R root:root "$DIR"
	chmod 755 "$DIR" "$DIR/php" "$DIR/apache" "$DIR/backup" "$DIR/wp-php8.sh"
	chmod 644 "$DIR/docker-compose.yml" "$DIR/.env" "$DIR/php/zz-custom.ini" "$DIR/apache/"*.conf
	# PHP writes its error log here as the web user.
	chown "$WEB_UID:$WEB_UID" "$DIR/logs"
	chmod 755 "$DIR/logs"
	[ -f "$DIR/backup/vhost-original.conf" ] || cp -p "$VHOST" "$DIR/backup/vhost-original.conf"
}

cmd=${1:-status}
need_root "$cmd"

case "$cmd" in
	install)
		[ -f "$(dirname "$0")/.env" ] || { say "copy .env.example to .env and edit it first"; exit 1; }
		install_files
		say "installed to $DIR"
		$COMPOSE pull && $COMPOSE up -d --force-recreate || exit 1
		if wait_healthy; then
			say "container answers normally. The site still runs on PHP 7.4 until you run 'switch'."
		else
			say "container did not answer within 90 s. Check 'logs'. The site still runs on PHP 7.4."
		fi
		sh "$DIR/wp-php8.sh" status
		healthy || exit 1
		;;
	up)
		$COMPOSE up -d && wait_healthy && say "container healthy"
		;;
	reinstall)
		install_files
		if ! $COMPOSE up -d --force-recreate; then
			touch "$PIN"; do_rollback
			say "could not recreate the container; rolled back to PHP 7.4"
			exit 1
		fi
		if wait_healthy; then
			rm -f "$PIN"
			case "$(points_to)" in container*) ;; *) do_switch ;; esac
			say "reinstalled: $(points_to)"
		else
			touch "$PIN"; do_rollback
			say "new container is not answering; rolled back to PHP 7.4. Logs:"
			$DOCKER logs --tail 30 "$CONTAINER" 2>&1
			exit 1
		fi
		;;
	fixowner)
		n=$(find "$WP_DIR" "$DIR/logs" -uid 0 2>/dev/null | wc -l)
		find "$WP_DIR" "$DIR/logs" -uid 0 -exec chown "$WEB_UID:$WEB_UID" {} +
		say "gave $n root-owned files back to uid $WEB_UID"
		;;
	update)
		$COMPOSE pull && $COMPOSE up -d || exit 1
		if wait_healthy; then say "restarted on the new image, healthy"; else say "new image is not answering; check 'logs', 'rollback' if needed"; fi
		;;
	status)
		$DOCKER ps -a --filter "name=$CONTAINER" --format 'container: {{.Names}} / {{.Status}} / {{.Image}}'
		$DOCKER exec "$CONTAINER" sh -c 'echo "runs as: $(id -u):$(id -g)"' 2>/dev/null
		$DOCKER exec "$CONTAINER" php -r 'echo "PHP ", PHP_VERSION, " / memory_limit ", ini_get("memory_limit"), PHP_EOL;' 2>/dev/null
		if healthy; then say "test request: OK (wp-login 200, home 200)"; else say "test request: FAILED"; fi
		say "nginx points to: $(points_to)"
		[ -f "$PIN" ] && say "pinned to rollback ('ensure' will not switch back on its own)"
		exit 0
		;;
	switch)
		healthy || { say "container is not answering; not switching"; exit 1; }
		rm -f "$PIN"
		if do_switch; then say "switched: $(points_to)"; else say "switch failed, left as is: $(points_to)"; exit 1; fi
		;;
	rollback)
		touch "$PIN"
		do_rollback && say "rolled back: $(points_to)"
		;;
	ensure)
		# Keep the PHP error log small.
		f="$DIR/logs/php-error.log"
		if [ -f "$f" ] && [ "$(wc -c < "$f")" -gt 20000000 ]; then
			tail -n 2000 "$f" > "$f.tmp" && cat "$f.tmp" > "$f" && rm -f "$f.tmp"
		fi
		[ -f "$PIN" ] && exit 0
		case "$(points_to)" in
			webstation*)
				if healthy && do_switch; then
					echo "$(date '+%F %T') Web Station rewrote its nginx file; switched back to the container" >> "$LOG"
				fi
				;;
			container*)
				if ! healthy; then
					sleep 20
					if ! healthy && do_rollback; then
						echo "$(date '+%F %T') container not answering; fell back to PHP 7.4" >> "$LOG"
					fi
				fi
				;;
		esac
		;;
	down)
		touch "$PIN"; do_rollback
		$COMPOSE down
		say "container stopped; site runs on $(points_to)"
		;;
	logs)
		say "PHP error log (last 40 lines):"
		tail -n 40 "$DIR/logs/php-error.log" 2>/dev/null || echo "(none)"
		say "Apache log (last 40 lines):"
		$DOCKER logs --tail 40 "$CONTAINER" 2>&1
		;;
	*)
		say "usage: sudo sh $0 install|status|switch|rollback|ensure|update|reinstall|fixowner|up|down|logs"
		exit 2
		;;
esac
