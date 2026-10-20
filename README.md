# dsm6-wordpress-homeserver

Small scripts for running a self-hosted WordPress blog on a **Synology DSM 6.2** NAS behind **Cloudflare**.
They come from the setup behind [lavient.life](https://lavient.life), a personal blog served from a home NAS.

| Folder | What it does |
|---|---|
| [`php8-docker/`](php8-docker/) | Run the existing WordPress folder on **PHP 8.3 in Docker**, because DSM 6.2's Web Station stops at PHP 7.4. Only one `proxy_pass` line in DSM nginx changes; one command rolls back. |
| [`cloudflare-realip/`](cloudflare-realip/) | Make DSM's nginx trust Cloudflare and **restore real visitor IPs** for every site on the NAS, so DSM Auto Block bans attackers instead of Cloudflare's edge IPs. |
| [`wordpress-mu-plugins/`](wordpress-mu-plugins/) | `cloudflare-real-ip.php`: the same IP fix inside WordPress (fallback). `yoast-rest-meta.php`: lets authenticated REST requests set the Yoast SEO title, description and focus keyphrase. |

## Before you start

- Tested on one machine: DSM 6.2.3, Web Station with PHP 7.4, MariaDB 10, Docker package, WordPress 7.1. Treat it as a starting point and read each script before running it as root.
- Back up your database, `wp-config.php`, `.htaccess` and `/etc/nginx/app.d/server.webstation-vhost.conf` first.
- Both shell scripts need DSM **Task Scheduler** entries (root, every 10 minutes) running their `ensure` command, because DSM rewrites the files they touch.
- Settings live at the top of each script (and in `.env` for Docker). Replace `example.com`, paths and the NAS IP with yours.

## Write-ups (Korean)

- [DSM 6.2에서 PHP 8 쓰기 – 도커로 워드프레스 PHP 8.3 전환](https://lavient.life/synology-dsm6-php8-docker/)
- [집 서버 보안 설정 – Cloudflare로 IP 숨기고 공격 막기](https://lavient.life/home-server-cloudflare-security/)
- [NAS를 인터넷에 열면 생기는 일 – 2년간 IP 17,864개 차단 기록](https://lavient.life/nas-attack-data-2-years/)

## 한국어 요약

DSM 6.2 NAS에서 워드프레스를 운영하면서 만든 스크립트 모음입니다.

- `php8-docker/`: 패키지 센터에 PHP 8이 없는 DSM 6.2에서, 기존 워드프레스 폴더를 그대로 두고 도커 컨테이너(PHP 8.3)로 서비스합니다. 문제가 생기면 `rollback` 한 번으로 PHP 7.4로 돌아갑니다.
- `cloudflare-realip/`: Cloudflare 프록시 뒤에서 DSM nginx가 실제 방문자 IP를 보게 합니다. DSM 자동 차단이 Cloudflare IP를 막아 나와 가족이 잠기는 일을 막습니다.
- `wordpress-mu-plugins/`: 워드프레스용 보조 플러그인 두 개.

root 권한으로 도는 스크립트이니 꼭 내용을 읽어 보고, 백업 후에 쓰세요.

## License

MIT
