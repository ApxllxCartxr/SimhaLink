class MapConfig {
  // Use your own Mapbox access token here
  static const String mapboxAccessToken = 'pk.YOUR_MAPBOX_TOKEN';
  
  static const String lightStyle = 'mapbox/light-v11';
  
  static String get lightStyleUrl => 
    'https://api.mapbox.com/styles/v1/$lightStyle/tiles/{z}/{x}/{y}?access_token=$mapboxAccessToken';
}
