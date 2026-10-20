<?php
/**
 * Plugin Name: Yoast SEO fields in the REST API
 * Description: Lets authenticated editors read/write the Yoast SEO title, meta description and focus keyphrase through the REST API, so drafts created by scripts or AI tools can carry their SEO fields.
 *
 * Install: copy to wp-content/mu-plugins/yoast-rest-meta.php (create the folder if missing).
 */

add_action( 'init', function () {
	foreach ( array( '_yoast_wpseo_title', '_yoast_wpseo_metadesc', '_yoast_wpseo_focuskw' ) as $key ) {
		register_post_meta(
			'post',
			$key,
			array(
				'type'          => 'string',
				'single'        => true,
				'show_in_rest'  => true,
				'auth_callback' => function ( $allowed, $meta_key, $post_id ) {
					return current_user_can( 'edit_post', $post_id );
				},
			)
		);
	}
} );
