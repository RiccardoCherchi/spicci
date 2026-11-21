/// Sossoldi stores Material icon names; Spicci stores Solar names.
/// Unknown names fall back to "tag" when drawn.
const materialToSolar = <String, String>{
  // Household
  'home': 'home-2', 'weekend': 'sofa', 'blender': 'fridge', 'construction': 'sledgehammer',
  'shopping_cart': 'cart-large-2', 'dry_cleaning': 'hanger', 'checkroom': 'hanger', 'lightbulb': 'lightbulb',
  'electrical_services': 'plug', 'energy_savings_leaf': 'leaf', 'router': 'wi-fi-router',
  'device_thermostat': 'sun', 'water_drop': 'waterdrop', 'local_fire_department': 'fire',
  'local_gas_station': 'gas-station', 'ev_station': 'bolt', 'bakery_dining': 'cake', 'cookie': 'cake',
  'fastfood': 'burger', 'bedroom_baby': 'bed', 'cake': 'cake', 'balance': 'document-text',
  'dinner_dining': 'chef-hat', 'liquor': 'wineglass', 'restaurant': 'chef-hat', 'ramen_dining': 'chef-hat',
  'vaccines': 'syringe', 'medication': 'pill', 'smoking_rooms': 'cigarette', 'vaping_rooms': 'cigarette',
  'airline_seat_flat': 'bed', 'child_friendly': 'smile-circle', 'pets': 'paw',
  // Activities
  'work': 'case', 'school': 'square-academic-cap', 'calendar_month': 'hourglass',
  'videogame_asset': 'gamepad', 'translate': 'globe', 'menu_book': 'book', 'palette': 'palette',
  'biotech': 'medical-kit', 'design_services': 'palette', 'celebration': 'confetti', 'card_giftcard': 'gift',
  'shopping_bag': 'bag-4', 'format_paint': 'palette', 'park': 'tree', 'attractions': 'balloon',
  'festival_outlined': 'confetti', 'stadium': 'football', 'theater_comedy': 'ticket', 'movie': 'clapperboard-play',
  'local_activity': 'ticket', 'church': 'star', 'store': 'shop', 'beach_access': 'umbrella',
  'fitness_center': 'dumbbell-large', 'workspace_premium': 'medal-ribbon-star', 'emoji_events': 'medal-ribbon-star',
  'sports_motorsports': 'scooter', 'sports_tennis': 'football', 'golf_course': 'flag',
  'sports_volleyball': 'football', 'sports_football': 'football', 'sports_soccer': 'football',
  'sports_basketball': 'football', 'rocket_launch': 'magic-wand',
  // Travel
  'flight': 'plane', 'local_taxi': 'car', 'directions_boat': 'ship', 'sailing': 'ship', 'anchor': 'ship',
  'agriculture': 'leaf', 'commute': 'bus', 'directions_bus': 'bus', 'directions_railway': 'tram',
  'tram': 'tram', 'electric_scooter': 'kick-scooter', 'directions_car': 'car', 'electric_car': 'car',
  'local_shipping': 'truck', 'electric_rickshaw': 'scooter', 'pedal_bike': 'bicycle', 'electric_bike': 'bicycle',
  'two_wheeler': 'scooter', 'moped': 'scooter', 'electric_moped': 'scooter', 'public': 'globe',
  'place': 'map', 'hotel': 'bed', 'luggage': 'suitcase', 'airplane_ticket': 'ticket',
  'airline_seat_recline_normal': 'plane',
  // Tech
  'desktop_mac': 'laptop', 'laptop': 'laptop', 'devices': 'smartphone', 'phone_iphone': 'smartphone',
  'sim_card': 'smartphone', 'camera_alt': 'camera', 'image': 'camera', 'language': 'globe',
  'library_music': 'music-note', 'subscriptions': 'tv', 'music_note': 'music-note', 'cloud': 'refresh-circle',
  'call': 'smartphone', 'headphones': 'headphones-round', 'shield': 'shield-check', 'drafts': 'document-text',
  // People
  'wc': 'users-group-rounded', 'pregnant_woman': 'user', 'diversity_3': 'users-group-rounded',
  'family_restroom': 'users-group-rounded', 'accessible': 'user', 'elderly': 'user', 'elderly_woman': 'user',
  'self_improvement': 'smile-circle', 'sports_martial_arts': 'running', 'downhill_skiing': 'mountains',
  'directions_run': 'running', 'directions_bike': 'bicycle', 'hiking': 'mountains', 'face_4': 'user',
  'child_care': 'smile-circle', 'face': 'user', 'face_3': 'user',
  // Others
  'real_estate_agent': 'key', 'auto_graph': 'chart', 'diamond': 'crown', 'local_parking': 'parking',
  'emergency': 'medical-kit', 'vpn_key': 'key', 'bolt': 'bolt', 'filter_vintage': 'leaf', 'ac_unit': 'sun',
  'wb_sunny': 'sun', 'mode_night': 'star', 'recycling': 'refresh-circle', 'favorite': 'heart', 'star': 'star',
  'priority_high': 'danger-triangle', 'volunteer_activism': 'hand-heart', 'psychology': 'smile-circle',
  'push_pin': 'flag', 'question_mark': 'question-circle', 'flag': 'flag', 'percent': 'percent',
  'alternate_email': 'document-text', 'block': 'danger-triangle', 'attach_file': 'document-text',
  'sos': 'danger-triangle',
  // Accounts
  'payments': 'banknote', 'credit_card': 'card', 'savings': 'piggy-bank', 'account_balance': 'bank',
};
