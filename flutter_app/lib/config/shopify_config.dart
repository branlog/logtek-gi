class ShopifyConfig {
  static const String domain = String.fromEnvironment(
    'SHOPIFY_STORE_DOMAIN',
    defaultValue: '',
  );

  static const String storefrontToken = String.fromEnvironment(
    'SHOPIFY_STOREFRONT_TOKEN',
    defaultValue: '',
  );

  // Si un jour on réactive un login côté backend, on rajoutera ici:
  // static const String loginEndpoint = String.fromEnvironment('SHOPIFY_LOGIN_ENDPOINT', defaultValue: '');
}
