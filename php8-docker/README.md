# PHP 8.3 for WordPress on DSM 6.2 (Docker)

DSM 6.2's Package Center offers PHP up to 7.4. This runs the **same WordPress folder and database** in the
`wordpress:php8.3-apache` image and points DSM nginx at it. Web Station stays installed as the fallback.

```
visitor → DSM nginx (HTTPS, certificate) ─┬→ 127.0.0.1:915   Web Station Apache + PHP 7.4  (fallback)
                                          └→ 127.0.0.1:8083  container Apache + PHP 8.3     (switched)
```

## Install

1. Install the **Docker** package from Package Center.
2. Copy this folder to the NAS, then `cp .env.example .env` and edit it (WordPress path, web user uid, port, MariaDB socket folder).
3. Edit the settings block at the top of `wp-php8.sh` (domain, install folder, same port).
4. `sudo sh wp-php8.sh install` — copies everything to `DIR`, starts the container, checks that `/wp-login.php` and `/` answer 200. The site is **not** switched yet.
5. `sudo sh <DIR>/wp-php8.sh switch` — changes `proxy_pass` in `/etc/nginx/app.d/server.webstation-vhost.conf` and reloads nginx (only if `nginx -t` passes).
6. DSM → Control Panel → Task Scheduler → Create → Scheduled Task → User-defined script: user **root**, daily, every **10 minutes** until 23:50:
   `/bin/sh <DIR>/wp-php8.sh ensure`

Web Station rewrites its nginx file after reboots, setting changes and certificate renewals, which silently puts the site back on PHP 7.4. `ensure` switches it back — and falls back to PHP 7.4 by itself if the container stops answering.

## Commands

| Command | |
|---|---|
| `status` | container, PHP version, test request, where nginx points |
| `switch` / `rollback` | PHP 8.3 / back to PHP 7.4 (rollback stays until the next switch) |
| `update` | pull the newest PHP 8.3 image (security fixes) |
| `fixowner` | files written as root go back to the web user |
| `logs` | PHP error log and Apache log |

## Gotchas we hit

- **The container must not run as root.** Setting only Apache's run user still leaves root-owned files behind. `user: "${WEB_UID}:${WEB_GID}"` runs everything as the web user; non-root Apache can't bind port 80, hence port 8080 inside.
- **Same path inside and outside** (`${WP_DIR}:${WP_DIR}`): plugins store absolute paths.
- **Real IP and HTTPS**: `remoteip.conf` trusts DSM nginx's `X-Real-IP` and `X-Forwarded-Proto` only from the Docker bridge.
- **WP-CLI** on the host still uses PHP 7.4, so plugins that require PHP 8+ must be installed from wp-admin.
- **Mail**: DSM's mail relay is empty by default, so WordPress mail never left the box before either. Use an SMTP plugin.
