/**
 * locale.ts — Regional settings definitions and formatting utilities.
 *
 * All data stored in the DB uses metric SI units (kg, cm, km) and ISO dates.
 * These helpers convert for display only — nothing is re-stored after conversion.
 */

export interface FamilySettings {
  country: string;
  locale: string;       // BCP 47 tag  e.g. 'en-US'
  timezone: string;     // IANA tz     e.g. 'America/New_York'
  units: 'metric' | 'imperial';
  currencyCode: string; // ISO 4217    e.g. 'USD'
  timeFormat: '12h' | '24h';
  firstDayOfWeek: 0 | 1 | 6; // 0=Sunday, 1=Monday, 6=Saturday
}

export interface CountryDef {
  code: string;
  name: string;
  flag: string;
  locale: string;
  timezone: string;
  units: 'metric' | 'imperial';
  currencyCode: string;
  timeFormat: '12h' | '24h';
  firstDayOfWeek: 0 | 1 | 6; // 0=Sunday, 1=Monday, 6=Saturday
}

export const COUNTRIES: CountryDef[] = [
  { code: 'US', name: 'United States',   flag: '🇺🇸', locale: 'en-US', timezone: 'America/New_York',       units: 'imperial', currencyCode: 'USD', timeFormat: '12h', firstDayOfWeek: 0 },
  { code: 'GB', name: 'United Kingdom',  flag: '🇬🇧', locale: 'en-GB', timezone: 'Europe/London',           units: 'metric',   currencyCode: 'GBP', timeFormat: '12h', firstDayOfWeek: 1 },
  { code: 'CA', name: 'Canada',          flag: '🇨🇦', locale: 'en-CA', timezone: 'America/Toronto',         units: 'metric',   currencyCode: 'CAD', timeFormat: '12h', firstDayOfWeek: 0 },
  { code: 'AU', name: 'Australia',       flag: '🇦🇺', locale: 'en-AU', timezone: 'Australia/Sydney',        units: 'metric',   currencyCode: 'AUD', timeFormat: '12h', firstDayOfWeek: 1 },
  { code: 'NZ', name: 'New Zealand',     flag: '🇳🇿', locale: 'en-NZ', timezone: 'Pacific/Auckland',        units: 'metric',   currencyCode: 'NZD', timeFormat: '12h', firstDayOfWeek: 1 },
  { code: 'ZA', name: 'South Africa',    flag: '🇿🇦', locale: 'en-ZA', timezone: 'Africa/Johannesburg',     units: 'metric',   currencyCode: 'ZAR', timeFormat: '12h', firstDayOfWeek: 1 },
  { code: 'IE', name: 'Ireland',         flag: '🇮🇪', locale: 'en-IE', timezone: 'Europe/Dublin',           units: 'metric',   currencyCode: 'EUR', timeFormat: '12h', firstDayOfWeek: 1 },
  { code: 'DE', name: 'Germany',         flag: '🇩🇪', locale: 'de-DE', timezone: 'Europe/Berlin',           units: 'metric',   currencyCode: 'EUR', timeFormat: '24h', firstDayOfWeek: 1 },
  { code: 'FR', name: 'France',          flag: '🇫🇷', locale: 'fr-FR', timezone: 'Europe/Paris',            units: 'metric',   currencyCode: 'EUR', timeFormat: '24h', firstDayOfWeek: 1 },
  { code: 'NL', name: 'Netherlands',     flag: '🇳🇱', locale: 'nl-NL', timezone: 'Europe/Amsterdam',        units: 'metric',   currencyCode: 'EUR', timeFormat: '24h', firstDayOfWeek: 1 },
  { code: 'BE', name: 'Belgium',         flag: '🇧🇪', locale: 'nl-BE', timezone: 'Europe/Brussels',         units: 'metric',   currencyCode: 'EUR', timeFormat: '24h', firstDayOfWeek: 1 },
  { code: 'ES', name: 'Spain',           flag: '🇪🇸', locale: 'es-ES', timezone: 'Europe/Madrid',           units: 'metric',   currencyCode: 'EUR', timeFormat: '24h', firstDayOfWeek: 1 },
  { code: 'IT', name: 'Italy',           flag: '🇮🇹', locale: 'it-IT', timezone: 'Europe/Rome',             units: 'metric',   currencyCode: 'EUR', timeFormat: '24h', firstDayOfWeek: 1 },
  { code: 'PT', name: 'Portugal',        flag: '🇵🇹', locale: 'pt-PT', timezone: 'Europe/Lisbon',           units: 'metric',   currencyCode: 'EUR', timeFormat: '24h', firstDayOfWeek: 1 },
  { code: 'CH', name: 'Switzerland',     flag: '🇨🇭', locale: 'de-CH', timezone: 'Europe/Zurich',           units: 'metric',   currencyCode: 'CHF', timeFormat: '24h', firstDayOfWeek: 1 },
  { code: 'SE', name: 'Sweden',          flag: '🇸🇪', locale: 'sv-SE', timezone: 'Europe/Stockholm',        units: 'metric',   currencyCode: 'SEK', timeFormat: '24h', firstDayOfWeek: 1 },
  { code: 'NO', name: 'Norway',          flag: '🇳🇴', locale: 'nb-NO', timezone: 'Europe/Oslo',             units: 'metric',   currencyCode: 'NOK', timeFormat: '24h', firstDayOfWeek: 1 },
  { code: 'DK', name: 'Denmark',         flag: '🇩🇰', locale: 'da-DK', timezone: 'Europe/Copenhagen',       units: 'metric',   currencyCode: 'DKK', timeFormat: '24h', firstDayOfWeek: 1 },
  { code: 'IN', name: 'India',           flag: '🇮🇳', locale: 'en-IN', timezone: 'Asia/Kolkata',            units: 'metric',   currencyCode: 'INR', timeFormat: '12h', firstDayOfWeek: 0 },
  { code: 'SG', name: 'Singapore',       flag: '🇸🇬', locale: 'en-SG', timezone: 'Asia/Singapore',         units: 'metric',   currencyCode: 'SGD', timeFormat: '12h', firstDayOfWeek: 1 },
  { code: 'MY', name: 'Malaysia',        flag: '🇲🇾', locale: 'en-MY', timezone: 'Asia/Kuala_Lumpur',       units: 'metric',   currencyCode: 'MYR', timeFormat: '12h', firstDayOfWeek: 1 },
  { code: 'PH', name: 'Philippines',     flag: '🇵🇭', locale: 'en-PH', timezone: 'Asia/Manila',             units: 'metric',   currencyCode: 'PHP', timeFormat: '12h', firstDayOfWeek: 0 },
  { code: 'AE', name: 'UAE',             flag: '🇦🇪', locale: 'en-AE', timezone: 'Asia/Dubai',              units: 'metric',   currencyCode: 'AED', timeFormat: '12h', firstDayOfWeek: 6 },
  { code: 'JP', name: 'Japan',           flag: '🇯🇵', locale: 'ja-JP', timezone: 'Asia/Tokyo',              units: 'metric',   currencyCode: 'JPY', timeFormat: '24h', firstDayOfWeek: 0 },
  { code: 'KR', name: 'South Korea',     flag: '🇰🇷', locale: 'ko-KR', timezone: 'Asia/Seoul',              units: 'metric',   currencyCode: 'KRW', timeFormat: '12h', firstDayOfWeek: 0 },
  { code: 'BR', name: 'Brazil',          flag: '🇧🇷', locale: 'pt-BR', timezone: 'America/Sao_Paulo',       units: 'metric',   currencyCode: 'BRL', timeFormat: '24h', firstDayOfWeek: 0 },
  { code: 'MX', name: 'Mexico',          flag: '🇲🇽', locale: 'es-MX', timezone: 'America/Mexico_City',     units: 'metric',   currencyCode: 'MXN', timeFormat: '12h', firstDayOfWeek: 0 },
  { code: 'NG', name: 'Nigeria',         flag: '🇳🇬', locale: 'en-NG', timezone: 'Africa/Lagos',            units: 'metric',   currencyCode: 'NGN', timeFormat: '12h', firstDayOfWeek: 1 },
  { code: 'KE', name: 'Kenya',           flag: '🇰🇪', locale: 'en-KE', timezone: 'Africa/Nairobi',          units: 'metric',   currencyCode: 'KES', timeFormat: '12h', firstDayOfWeek: 1 },
  { code: 'GH', name: 'Ghana',           flag: '🇬🇭', locale: 'en-GH', timezone: 'Africa/Accra',            units: 'metric',   currencyCode: 'GHS', timeFormat: '12h', firstDayOfWeek: 1 },
];

// Detect a sensible default from the browser
function detectBrowserDefaults(): Partial<FamilySettings> {
  try {
    const tz = Intl.DateTimeFormat().resolvedOptions().timeZone;
    const locale = navigator.language || 'en-US';
    return { timezone: tz, locale };
  } catch {
    return {};
  }
}

export const DEFAULT_SETTINGS: FamilySettings = {
  country: 'US',
  locale: 'en-US',
  timezone: 'America/New_York',
  units: 'imperial',
  currencyCode: 'USD',
  timeFormat: '12h',
  firstDayOfWeek: 0,
  ...detectBrowserDefaults(),
};

export function getCountryDefaults(code: string): FamilySettings {
  const c = COUNTRIES.find(x => x.code === code);
  if (!c) return DEFAULT_SETTINGS;
  return {
    country: c.code,
    locale: c.locale,
    timezone: c.timezone,
    units: c.units,
    currencyCode: c.currencyCode,
    timeFormat: c.timeFormat,
    firstDayOfWeek: c.firstDayOfWeek,
  };
}

// ---------------------------------------------------------------------------
// "Today" as a local-timezone YYYY-MM-DD string (fixes the UTC date bug)
// Using en-CA locale which outputs yyyy-MM-dd format natively
// ---------------------------------------------------------------------------
export function localDateStr(timezone?: string): string {
  try {
    return new Intl.DateTimeFormat('en-CA', {
      timeZone: timezone || Intl.DateTimeFormat().resolvedOptions().timeZone,
    }).format(new Date());
  } catch {
    // Fallback: use device local time
    const d = new Date();
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
  }
}

// ---------------------------------------------------------------------------
// Date / time formatting
// ---------------------------------------------------------------------------
export function fmtDate(date: Date, s: FamilySettings): string {
  return new Intl.DateTimeFormat(s.locale, {
    month: 'short', day: 'numeric', year: 'numeric', timeZone: s.timezone,
  }).format(date);
}

export function fmtDateShort(date: Date, s: FamilySettings): string {
  return new Intl.DateTimeFormat(s.locale, {
    month: 'short', day: 'numeric', timeZone: s.timezone,
  }).format(date);
}

export function fmtTime(date: Date, s: FamilySettings): string {
  return new Intl.DateTimeFormat(s.locale, {
    hour: 'numeric', minute: '2-digit', hour12: s.timeFormat === '12h', timeZone: s.timezone,
  }).format(date);
}

export function fmtDateTime(date: Date, s: FamilySettings): string {
  return new Intl.DateTimeFormat(s.locale, {
    month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit',
    hour12: s.timeFormat === '12h', timeZone: s.timezone,
  }).format(date);
}

export function fmtDateLong(date: Date, s: FamilySettings): string {
  return new Intl.DateTimeFormat(s.locale, {
    weekday: 'long', month: 'long', day: 'numeric', timeZone: s.timezone,
  }).format(date);
}

export function fmtMonthYear(date: Date, s: FamilySettings): string {
  return new Intl.DateTimeFormat(s.locale, {
    month: 'long', year: 'numeric', timeZone: s.timezone,
  }).format(date);
}

// ---------------------------------------------------------------------------
// Currency
// ---------------------------------------------------------------------------
export function fmtCurrency(amount: number, s: FamilySettings): string {
  return new Intl.NumberFormat(s.locale, {
    style: 'currency', currency: s.currencyCode,
    minimumFractionDigits: 0, maximumFractionDigits: 2,
  }).format(amount);
}

export function fmtCurrencyCompact(amount: number, s: FamilySettings): string {
  return new Intl.NumberFormat(s.locale, {
    style: 'currency', currency: s.currencyCode, maximumFractionDigits: 0,
  }).format(amount);
}

export function getCurrencySymbol(s: FamilySettings): string {
  const parts = new Intl.NumberFormat(s.locale, {
    style: 'currency', currency: s.currencyCode,
  }).formatToParts(1);
  return parts.find(p => p.type === 'currency')?.value ?? s.currencyCode;
}

// ---------------------------------------------------------------------------
// Weight  (DB stores kg, display converts if imperial)
// ---------------------------------------------------------------------------
export function weightUnit(s: FamilySettings): string {
  return s.units === 'imperial' ? 'lbs' : 'kg';
}

export function kgToDisplay(kg: number, s: FamilySettings): number {
  return s.units === 'imperial' ? Math.round(kg * 2.20462 * 10) / 10 : kg;
}

export function displayToKg(value: number, s: FamilySettings): number {
  return s.units === 'imperial' ? Math.round((value / 2.20462) * 10) / 10 : value;
}

export function fmtWeight(kg: number, s: FamilySettings): string {
  return `${kgToDisplay(kg, s)} ${weightUnit(s)}`;
}

// ---------------------------------------------------------------------------
// Height  (DB stores cm, display converts if imperial → ft + in)
// ---------------------------------------------------------------------------
export function heightUnit(s: FamilySettings): string {
  return s.units === 'imperial' ? 'in' : 'cm';
}

export function cmToDisplayVal(cm: number, s: FamilySettings): number {
  // Returns inches when imperial (useful for single-field inputs)
  return s.units === 'imperial' ? Math.round(cm / 2.54) : cm;
}

export function displayToCm(value: number, s: FamilySettings): number {
  return s.units === 'imperial' ? Math.round(value * 2.54) : value;
}

export function fmtHeight(cm: number, s: FamilySettings): string {
  if (s.units === 'imperial') {
    const totalIn = Math.round(cm / 2.54);
    const ft = Math.floor(totalIn / 12);
    const inches = totalIn % 12;
    return `${ft}'${inches}"`;
  }
  return `${cm} cm`;
}

// ---------------------------------------------------------------------------
// Distance  (DB stores km, display converts if imperial)
// ---------------------------------------------------------------------------
export function distanceUnit(s: FamilySettings): string {
  return s.units === 'imperial' ? 'mi' : 'km';
}

export function kmToDisplay(km: number, s: FamilySettings): number {
  return s.units === 'imperial' ? Math.round(km * 0.621371 * 10) / 10 : km;
}

export function fmtDistance(km: number, s: FamilySettings): string {
  return `${kmToDisplay(km, s)} ${distanceUnit(s)}`;
}
