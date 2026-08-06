export function normalizePhone(value, defaultCountryCode = '57') {
  let phone = String(value || '').replace(/\D/g, '');
  if (phone.startsWith('00')) phone = phone.slice(2);
  if (phone.length === 10) phone = `${defaultCountryCode}${phone}`;
  return phone;
}

export function createWhatsAppUrl(phone, message) {
  return `https://wa.me/${normalizePhone(phone)}?text=${encodeURIComponent(message)}`;
}
