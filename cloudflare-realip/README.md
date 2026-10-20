# Real visitor IPs behind Cloudflare on DSM 6.2

With Cloudflare's proxy (orange cloud) on, every request reaches the NAS from a Cloudflare edge IP. Two things break:

- **DSM Auto Block** counts failed logins per IP. It ends up banning a Cloudflare edge IP — locking out you and your family — while attackers are never told apart.
- WordPress comments, Akismet and login protection can't tell visitors apart either.

DSM 6.2's `nginx.conf` already restores the client IP from `X-Forwarded-For` and includes `/var/tmp/nginx/trusted_proxy/*.conf` for the list of trusted proxies — DSM 6.2 just has no screen to fill it. `realip.sh` writes that list: Cloudflare's ranges (`cloudflare-ranges.txt`) plus the NAS's own IP (for the DSM reverse proxy hop).

Requests that do not come from a trusted address keep their own IP, so `X-Forwarded-For` can't be spoofed by connecting to the NAS directly.

## Use

1. Set `NAS_IP` at the top of `realip.sh`.
2. `sudo sh realip.sh apply` (or `refresh` to download the current Cloudflare list first).
3. DSM Task Scheduler, user **root**, every **10 minutes**: `/bin/sh /path/to/realip.sh ensure`
4. `sudo sh realip.sh remove` undoes it.

Check it worked: log in to DSM through your Cloudflare-proxied hostname and look at **Log Center → Connection** — it should show your real public IP, not a Cloudflare one.
