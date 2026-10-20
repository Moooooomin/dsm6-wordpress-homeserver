<?php
/**
 * Plugin Name: Real visitor IP behind Cloudflare
 * Description: When a request arrives through Cloudflare, use CF-Connecting-IP as the visitor IP (comments, Akismet, Jetpack, Two-Factor, Redirection logs). Requests from anywhere else are left untouched, so the header cannot be spoofed.
 *
 * Install: copy to wp-content/mu-plugins/cloudflare-real-ip.php after the DNS records are proxied (orange cloud).
 * Fallback for when the web server itself does not restore the IP (see ../cloudflare-realip/).
 * Ranges: https://www.cloudflare.com/ips/ (fetched 2026-10-19).
 */

if ( empty( $_SERVER['HTTP_CF_CONNECTING_IP'] ) || empty( $_SERVER['REMOTE_ADDR'] ) ) {
	return;
}

function cfrip_ip_in_range( $ip, $cidr ) {
	list( $subnet, $bits ) = explode( '/', $cidr );
	$ip_bin     = @inet_pton( $ip );
	$subnet_bin = @inet_pton( $subnet );
	if ( false === $ip_bin || false === $subnet_bin || strlen( $ip_bin ) !== strlen( $subnet_bin ) ) {
		return false;
	}
	$bytes = intdiv( (int) $bits, 8 );
	$rest  = (int) $bits % 8;
	if ( substr( $ip_bin, 0, $bytes ) !== substr( $subnet_bin, 0, $bytes ) ) {
		return false;
	}
	if ( 0 === $rest ) {
		return true;
	}
	$mask = chr( ( 0xff << ( 8 - $rest ) ) & 0xff );
	return ( $ip_bin[ $bytes ] & $mask ) === ( $subnet_bin[ $bytes ] & $mask );
}

foreach ( array(
		'173.245.48.0/20',
		'103.21.244.0/22',
		'103.22.200.0/22',
		'103.31.4.0/22',
		'141.101.64.0/18',
		'108.162.192.0/18',
		'190.93.240.0/20',
		'188.114.96.0/20',
		'197.234.240.0/22',
		'198.41.128.0/17',
		'162.158.0.0/15',
		'104.16.0.0/13',
		'104.24.0.0/14',
		'172.64.0.0/13',
		'131.0.72.0/22',
		'2400:cb00::/32',
		'2606:4700::/32',
		'2803:f800::/32',
		'2405:b500::/32',
		'2405:8100::/32',
		'2a06:98c0::/29',
		'2c0f:f248::/32',
	) as $cfrip_range ) {
	if ( cfrip_ip_in_range( $_SERVER['REMOTE_ADDR'], $cfrip_range ) ) {
		$cfrip_visitor_ip = trim( $_SERVER['HTTP_CF_CONNECTING_IP'] );
		if ( filter_var( $cfrip_visitor_ip, FILTER_VALIDATE_IP ) ) {
			$_SERVER['REMOTE_ADDR'] = $cfrip_visitor_ip;
		}
		break;
	}
}
