export const arrivalRadiusMetres = 100;
export function hasArrived(site, location, now = Date.now()) {
  if (!location || now - new Date(location.updated_at).getTime() > 30000) return false;
  const radians = value => value * Math.PI / 180;
  const dLat = radians(location.lat - site.lat), dLng = radians(location.lng - site.lng);
  const a = Math.sin(dLat / 2) ** 2 + Math.cos(radians(site.lat)) * Math.cos(radians(location.lat)) * Math.sin(dLng / 2) ** 2;
  return 6371000 * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(Math.max(0, 1 - a))) <= arrivalRadiusMetres;
}
