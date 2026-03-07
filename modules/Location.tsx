import React, { useState, useEffect, useRef, useMemo, useCallback } from 'react';
import {
  MapPin, Navigation, Power, Plus, Trash2, X, RefreshCw,
  Home, School, Briefcase, Heart, Star, Clock, AlertCircle,
  CheckCircle2, Eye, EyeOff, Loader2,
} from 'lucide-react';
import { formatDistanceToNow, parseISO } from 'date-fns';
import { useRealtimeDB } from '../hooks/useRealtimeDB';
import { createId } from '../services/id';
import { supabase } from '../services/supabase';
import { User, Family, UserLocation, SavedPlace } from '../types';

// ── Constants ─────────────────────────────────────────────────────────────────

const PLACE_EMOJIS = ['🏠', '🏫', '💼', '🏥', '🛒', '⛪', '🏋️', '🌳', '🍕', '⭐'];

const AVATAR_COLORS = [
  'bg-indigo-500', 'bg-rose-500', 'bg-emerald-500', 'bg-amber-500',
  'bg-violet-500', 'bg-sky-500', 'bg-pink-500', 'bg-teal-500',
];

function avatarColor(id: string) {
  let h = 0;
  for (let i = 0; i < id.length; i++) h = (h * 31 + id.charCodeAt(i)) >>> 0;
  return AVATAR_COLORS[h % AVATAR_COLORS.length];
}

function initials(name: string) {
  if (!name?.trim()) return '?';
  return name.split(' ').map(p => p[0]).filter(Boolean).join('').toUpperCase().slice(0, 2) || '?';
}

/** Haversine distance in metres. */
function haversine(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const R = 6371000;
  const φ1 = (lat1 * Math.PI) / 180;
  const φ2 = (lat2 * Math.PI) / 180;
  const dφ = ((lat2 - lat1) * Math.PI) / 180;
  const dλ = ((lon2 - lon1) * Math.PI) / 180;
  const a = Math.sin(dφ / 2) ** 2 + Math.cos(φ1) * Math.cos(φ2) * Math.sin(dλ / 2) ** 2;
  return R * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

/** Nearest saved place within radius — returns the closest match, not just the first. */
function nearestPlace(lat: number, lon: number, places: SavedPlace[]): string | undefined {
  let best: SavedPlace | undefined;
  let bestDist = Infinity;
  for (const p of places) {
    const d = haversine(lat, lon, p.latitude, p.longitude);
    if (d <= p.radiusMetres && d < bestDist) {
      best = p;
      bestDist = d;
    }
  }
  return best?.name;
}

/** Reverse-geocode via Nominatim (free, no API key). */
async function reverseGeocode(lat: number, lon: number): Promise<string> {
  try {
    const res = await fetch(
      `https://nominatim.openstreetmap.org/reverse?lat=${lat}&lon=${lon}&format=json&addressdetails=1`,
      { headers: { 'Accept-Language': 'en' } },
    );
    const json = await res.json();
    const a = json.address;
    // Build a short human-readable label
    const parts = [
      a.road ?? a.pedestrian ?? a.suburb,
      a.suburb ?? a.city_district ?? a.neighbourhood,
      a.city ?? a.town ?? a.village,
    ].filter(Boolean);
    return parts.slice(0, 2).join(', ') || json.display_name?.split(',')[0] || 'Unknown location';
  } catch {
    return `${lat.toFixed(4)}, ${lon.toFixed(4)}`;
  }
}

// ── Props ─────────────────────────────────────────────────────────────────────

interface LocationProps { user: User; family: Family; }

// ── Component ─────────────────────────────────────────────────────────────────

const Location: React.FC<LocationProps> = ({ user, family }) => {
  const { db, save } = useRealtimeDB(user);

  const [isSharing, setIsSharing] = useState(false);
  const [myLocation, setMyLocation] = useState<GeolocationCoordinates | null>(null);
  const [placeName, setPlaceName] = useState<string | null>(null);
  const [geoError, setGeoError] = useState('');
  const [loading, setLoading] = useState(false);
  const watchIdRef = useRef<number | null>(null);
  const geocodeThrottleRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const dbRef = useRef(db);
  dbRef.current = db;

  // Places modal
  const [placesModal, setPlacesModal] = useState(false);
  const [placeName2, setPlaceName2] = useState('');
  const [placeEmoji, setPlaceEmoji] = useState('🏠');
  const [placeRadius, setPlaceRadius] = useState(200);
  const [detectedLocation, setDetectedLocation] = useState<{ lat: number; lon: number } | null>(null);

  // ── Data ────────────────────────────────────────────────────────────────────

  const familyMembers = useMemo(() =>
    (db.users || []).filter(u => (db.familyMembers || []).some(fm => fm.userId === u.id && fm.familyId === family.id)),
    [db.users, db.familyMembers, family.id]);

  const savedPlaces = useMemo(() =>
    (db.savedPlaces || []).filter(p => p.familyId === family.id),
    [db.savedPlaces, family.id]);

  const memberLocations = useMemo(() =>
    (db.userLocations || []).filter(l => l.familyId === family.id && l.isSharing),
    [db.userLocations, family.id]);

  const myStoredLocation = useMemo(() =>
    (db.userLocations || []).find(l => l.userId === user.id && l.familyId === family.id),
    [db.userLocations, user.id, family.id]);

  // Restore sharing state from stored location — restart watch so UI matches reality
  useEffect(() => {
    if (myStoredLocation?.isSharing) {
      startSharing();
    }
  }, []); // eslint-disable-line react-hooks/exhaustive-deps

  // ── Geolocation ─────────────────────────────────────────────────────────────

  const pushLocationUpdate = useCallback(async (coords: GeolocationCoordinates) => {
    const { latitude, longitude, accuracy } = coords;
    const near = nearestPlace(latitude, longitude, savedPlaces);

    // Throttle reverse geocode to once per 60s
    let name = placeName ?? undefined;
    if (!geocodeThrottleRef.current) {
      name = await reverseGeocode(latitude, longitude);
      setPlaceName(name);
      geocodeThrottleRef.current = setTimeout(() => { geocodeThrottleRef.current = null; }, 60000);
    }

    const entry: UserLocation = {
      id: user.id,
      familyId: family.id,
      userId: user.id,
      latitude,
      longitude,
      accuracy,
      placeName: name,
      nearPlace: near,
      isSharing: true,
      updatedAt: new Date().toISOString(),
    };

    const currentDb = dbRef.current;
    const existing = (currentDb.userLocations || []);
    const updated = existing.some(l => l.userId === user.id && l.familyId === family.id)
      ? existing.map(l => (l.userId === user.id && l.familyId === family.id) ? entry : l)
      : [...existing, entry];

    save({ ...currentDb, userLocations: updated }, 'updated location', 'Location', near ?? name ?? '');
  }, [family.id, user.id, save, savedPlaces, placeName]);

  const startSharing = useCallback(() => {
    if (!navigator.geolocation) {
      setGeoError('Location services are not available on this device.');
      return;
    }
    setLoading(true);
    setGeoError('');

    // On native Capacitor (Android/iOS), we do a one-shot getCurrentPosition first
    // so that the OS shows the permission dialog before we attach the watcher.
    // This prevents the watcher from silently failing on denied permissions.
    navigator.geolocation.getCurrentPosition(
      () => {
        // Permission granted — now start watching
        watchIdRef.current = navigator.geolocation.watchPosition(
          async (pos) => {
            setMyLocation(pos.coords);
            setLoading(false);
            await pushLocationUpdate(pos.coords);
          },
          (err) => {
            setLoading(false);
            setIsSharing(false);
            if (err.code === err.PERMISSION_DENIED) {
              setGeoError('Location permission denied. On Android, go to Settings → Apps → FamilyHub → Permissions → Location and set to "Allow only while using the app".');
            } else if (err.code === err.POSITION_UNAVAILABLE) {
              setGeoError('Location unavailable. Make sure GPS is enabled on your device.');
            } else {
              setGeoError('Could not get your location. Please try again.');
            }
            const currentDb = dbRef.current;
            const updated = (currentDb.userLocations || []).map(l =>
              (l.userId === user.id && l.familyId === family.id) ? { ...l, isSharing: false } : l
            );
            save({ ...currentDb, userLocations: updated });
          },
          { enableHighAccuracy: true, maximumAge: 30000, timeout: 15000 },
        );
        setIsSharing(true);
      },
      (err) => {
        setLoading(false);
        setIsSharing(false);
        if (err.code === err.PERMISSION_DENIED) {
          setGeoError('Location permission denied. On Android, go to Settings → Apps → FamilyHub → Permissions → Location and set to "Allow only while using the app".');
        } else {
          setGeoError('Could not start location sharing. Please check your device settings.');
        }
      },
      { enableHighAccuracy: true, timeout: 10000 },
    );
  }, [pushLocationUpdate, family.id, user.id, save]);

  const stopSharing = useCallback(() => {
    if (watchIdRef.current !== null) {
      navigator.geolocation.clearWatch(watchIdRef.current);
      watchIdRef.current = null;
    }
    if (geocodeThrottleRef.current) {
      clearTimeout(geocodeThrottleRef.current);
      geocodeThrottleRef.current = null;
    }
    setIsSharing(false);
    setMyLocation(null);
    setPlaceName(null);
    // Mark as not sharing in DB
    const currentDb = dbRef.current;
    const updated = (currentDb.userLocations || []).map(l =>
      (l.userId === user.id && l.familyId === family.id) ? { ...l, isSharing: false } : l
    );
    save({ ...currentDb, userLocations: updated }, 'stopped sharing location', 'Location', '');
  }, [family.id, user.id, save]);

  useEffect(() => {
    return () => {
      if (watchIdRef.current !== null) navigator.geolocation.clearWatch(watchIdRef.current);
      if (geocodeThrottleRef.current) clearTimeout(geocodeThrottleRef.current);
    };
  }, []);

  // ── Places ───────────────────────────────────────────────────────────────────

  const openAddPlace = () => {
    setPlaceName2('');
    setPlaceEmoji('🏠');
    setPlaceRadius(200);
    setDetectedLocation(myLocation ? { lat: myLocation.latitude, lon: myLocation.longitude } : null);
    setPlacesModal(true);
  };

  const handleSavePlace = () => {
    if (!placeName2.trim() || !detectedLocation) return;
    const place: SavedPlace = {
      id: createId(),
      familyId: family.id,
      creatorId: user.id,
      name: placeName2.trim(),
      emoji: placeEmoji,
      latitude: detectedLocation.lat,
      longitude: detectedLocation.lon,
      radiusMetres: placeRadius,
      createdAt: new Date().toISOString(),
    };
    save({ ...db, savedPlaces: [...(db.savedPlaces ?? []), place] }, 'added place', 'Location', place.name);
    setPlacesModal(false);
  };

  const handleDeletePlace = (id: string) => {
    save({ ...db, savedPlaces: (db.savedPlaces ?? []).filter(p => p.id !== id) }, 'deleted place', 'Location', '');
  };

  // ── Render ────────────────────────────────────────────────────────────────────

  return (
    <div className="space-y-6">
      {/* Header */}
      <header className="flex flex-col md:flex-row md:items-center justify-between gap-4">
        <div>
          <h1 className="text-3xl font-bold text-stone-900">Family Location</h1>
          <p className="text-stone-500">See where everyone is, safely and privately.</p>
        </div>
        <div className="flex gap-2">
          <button onClick={openAddPlace}
            className="flex items-center gap-2 px-4 py-2.5 bg-stone-50 text-stone-700 border border-stone-200 rounded-2xl font-bold hover:bg-stone-100 transition-colors">
            <Plus size={16} />Add Place
          </button>
        </div>
      </header>

      {/* My sharing toggle */}
      <div className={`rounded-3xl p-5 border-2 transition-all ${isSharing ? 'bg-gradient-to-r from-emerald-50 to-teal-50 border-emerald-200' : 'bg-white border-stone-200'}`}>
        <div className="flex items-center justify-between gap-4">
          <div className="flex items-center gap-4">
            <div className={`w-14 h-14 rounded-2xl flex items-center justify-center transition-colors ${isSharing ? 'bg-emerald-500' : 'bg-stone-200'}`}>
              {loading ? <Loader2 size={24} className="text-white animate-spin" /> : <Navigation size={24} className={isSharing ? 'text-white' : 'text-stone-400'} />}
            </div>
            <div>
              <p className="font-bold text-stone-800">
                {isSharing ? 'Sharing your location' : 'Location sharing is off'}
              </p>
              <p className="text-sm text-stone-500 mt-0.5">
                {isSharing
                  ? (myStoredLocation?.nearPlace
                    ? `📍 ${myStoredLocation.nearPlace}`
                    : placeName
                    ? `📍 ${placeName}`
                    : 'Getting your location…')
                  : 'Only you can see your own location when off'}
              </p>
            </div>
          </div>
          <button
            onClick={isSharing ? stopSharing : startSharing}
            className={`flex items-center gap-2 px-5 py-2.5 rounded-2xl font-bold transition-all ${isSharing ? 'bg-stone-200 text-stone-700 hover:bg-stone-300' : 'bg-emerald-600 text-white hover:bg-emerald-700 shadow-lg shadow-emerald-100'}`}
          >
            <Power size={16} />
            {isSharing ? 'Stop' : 'Share'}
          </button>
        </div>
        {geoError && (
          <div className="mt-3 flex items-start gap-2 text-sm text-red-600 bg-red-50 rounded-xl px-3 py-2.5">
            <AlertCircle size={16} className="shrink-0 mt-0.5" />
            {geoError}
          </div>
        )}
      </div>

      {/* Family members' locations */}
      <div className="space-y-3">
        <h3 className="text-sm font-black text-stone-400 uppercase tracking-widest">Family</h3>
        {familyMembers.length === 0 ? (
          <p className="text-sm text-stone-400">No other family members yet.</p>
        ) : (
          familyMembers.map(member => {
            const loc = memberLocations.find(l => l.userId === member.id);
            const isMe = member.id === user.id;
            const myLat = myLocation?.latitude;
            const myLon = myLocation?.longitude;
            const dist = (loc && myLat != null && myLon != null && !isMe)
              ? haversine(myLat, myLon, loc.latitude, loc.longitude)
              : null;
            const distLabel = dist !== null
              ? dist < 1000 ? `${Math.round(dist)} m away` : `${(dist / 1000).toFixed(1)} km away`
              : null;

            return (
              <div key={member.id} className="bg-white rounded-2xl border border-stone-100 p-4 flex items-center gap-4 shadow-sm">
                <div className={`w-12 h-12 rounded-full flex items-center justify-center text-white font-black text-sm shrink-0 ${avatarColor(member.id)}`}>
                  {initials(member.name)}
                </div>
                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <p className="font-bold text-stone-800">{member.name}{isMe && <span className="text-stone-400 font-normal"> (you)</span>}</p>
                    {(isMe && isSharing) || loc ? (
                      <span className="w-2 h-2 rounded-full bg-emerald-500 inline-block" title="Sharing" />
                    ) : (
                      <span className="w-2 h-2 rounded-full bg-stone-300 inline-block" title="Not sharing" />
                    )}
                  </div>
                  {isMe && isSharing ? (
                    <p className="text-sm text-stone-500 mt-0.5 truncate">
                      {myStoredLocation?.nearPlace
                        ? <><MapPin size={12} className="inline text-emerald-500 mr-0.5" />{myStoredLocation.nearPlace}</>
                        : placeName
                        ? <><MapPin size={12} className="inline text-stone-400 mr-0.5" />{placeName}</>
                        : 'Locating…'}
                    </p>
                  ) : loc ? (
                    <div className="space-y-0.5">
                      <p className="text-sm text-stone-500 truncate">
                        {loc.nearPlace
                          ? <><MapPin size={12} className="inline text-emerald-500 mr-0.5" />{loc.nearPlace}</>
                          : loc.placeName
                          ? <><MapPin size={12} className="inline text-stone-400 mr-0.5" />{loc.placeName}</>
                          : <span className="text-stone-300">Location available</span>}
                      </p>
                      <p className="text-xs text-stone-400 flex items-center gap-1">
                        <Clock size={10} />
                        {formatDistanceToNow(parseISO(loc.updatedAt), { addSuffix: true })}
                        {distLabel && <> · {distLabel}</>}
                      </p>
                    </div>
                  ) : (
                    <p className="text-sm text-stone-400 mt-0.5">Not sharing location</p>
                  )}
                </div>
                {loc && !isMe && (
                  <a
                    href={`https://maps.google.com/?q=${loc.latitude},${loc.longitude}`}
                    target="_blank"
                    rel="noopener noreferrer"
                    className="p-2 text-indigo-500 hover:bg-indigo-50 rounded-xl transition-colors shrink-0"
                    title="Open in Google Maps"
                  >
                    <Navigation size={18} />
                  </a>
                )}
              </div>
            );
          })
        )}
      </div>

      {/* Saved places */}
      <div className="space-y-3">
        <div className="flex items-center justify-between">
          <h3 className="text-sm font-black text-stone-400 uppercase tracking-widest">Saved Places</h3>
          <button onClick={openAddPlace}
            className="text-xs font-bold text-indigo-600 hover:text-indigo-700 flex items-center gap-1">
            <Plus size={12} />Add
          </button>
        </div>
        {savedPlaces.length === 0 ? (
          <div className="bg-white rounded-2xl border border-dashed border-stone-200 p-6 text-center text-stone-400">
            <MapPin size={28} className="mx-auto mb-2 text-stone-200" />
            <p className="text-sm font-medium">No saved places yet.</p>
            <p className="text-xs mt-1">Add Home, School or Work to get arrival alerts.</p>
          </div>
        ) : (
          <div className="grid grid-cols-2 sm:grid-cols-3 gap-3">
            {savedPlaces.map(p => (
              <div key={p.id} className="bg-white rounded-2xl border border-stone-100 p-4 flex items-center gap-3 group shadow-sm">
                <span className="text-2xl">{p.emoji}</span>
                <div className="flex-1 min-w-0">
                  <p className="font-bold text-stone-800 text-sm truncate">{p.name}</p>
                  <p className="text-xs text-stone-400">{p.radiusMetres} m radius</p>
                </div>
                {p.creatorId === user.id && (
                  <button onClick={() => handleDeletePlace(p.id)}
                    className="opacity-0 group-hover:opacity-100 p-1.5 text-stone-300 hover:text-red-500 rounded-lg transition-all">
                    <Trash2 size={13} />
                  </button>
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      {/* Privacy notice */}
      <div className="bg-stone-50 rounded-2xl border border-stone-200 p-4 flex items-start gap-3">
        <Eye size={16} className="text-stone-400 shrink-0 mt-0.5" />
        <div className="text-xs text-stone-500 space-y-1">
          <p className="font-bold text-stone-600">Privacy</p>
          <p>Location is only visible to your family circle. You can stop sharing at any time. Locations update every 30 seconds while sharing is active.</p>
        </div>
      </div>

      {/* Add Place Modal */}
      {placesModal && (
        <div className="fixed inset-0 z-50 flex items-end sm:items-center justify-center bg-black/50 p-4">
          <div className="bg-white rounded-3xl w-full max-w-md p-6 space-y-4">
            <div className="flex items-center justify-between">
              <h2 className="text-xl font-bold text-stone-800">Save a Place</h2>
              <button onClick={() => setPlacesModal(false)} className="p-2 hover:bg-stone-100 rounded-xl"><X size={20} /></button>
            </div>

            {/* Emoji */}
            <div>
              <label className="block text-sm font-bold text-stone-700 mb-2">Icon</label>
              <div className="flex flex-wrap gap-2">
                {PLACE_EMOJIS.map(e => (
                  <button key={e} type="button" onClick={() => setPlaceEmoji(e)}
                    className={`w-10 h-10 text-xl rounded-xl border-2 transition-all ${placeEmoji === e ? 'border-indigo-500 bg-indigo-50' : 'border-stone-200 hover:border-stone-300'}`}>
                    {e}
                  </button>
                ))}
              </div>
            </div>

            {/* Name */}
            <div>
              <label className="block text-sm font-bold text-stone-700 mb-1.5">Place Name</label>
              <input value={placeName2} onChange={e => setPlaceName2(e.target.value)} placeholder="e.g. Home, School, Work"
                className="w-full px-4 py-2.5 border border-stone-200 rounded-xl text-sm focus:outline-none focus:ring-2 focus:ring-indigo-300" />
            </div>

            {/* Location source */}
            <div className="bg-stone-50 rounded-xl p-3 text-sm text-stone-600 space-y-2">
              {detectedLocation ? (
                <div className="flex items-center gap-2 text-emerald-600">
                  <CheckCircle2 size={16} />
                  <span>Using your current location ({detectedLocation.lat.toFixed(4)}, {detectedLocation.lon.toFixed(4)})</span>
                </div>
              ) : (
                <div className="flex items-start gap-2 text-amber-600">
                  <AlertCircle size={16} className="shrink-0 mt-0.5" />
                  <span>Start sharing your location first, then add a place while you're there.</span>
                </div>
              )}
            </div>

            {/* Radius */}
            <div>
              <label className="block text-sm font-bold text-stone-700 mb-2">
                Detection Radius: <span className="text-indigo-600">{placeRadius} m</span>
              </label>
              <input type="range" min={50} max={1000} step={50} value={placeRadius} onChange={e => setPlaceRadius(Number(e.target.value))}
                className="w-full accent-indigo-600" />
              <div className="flex justify-between text-xs text-stone-400 mt-1">
                <span>50 m (precise)</span><span>1 km (loose)</span>
              </div>
            </div>

            <div className="flex gap-3">
              <button onClick={() => setPlacesModal(false)}
                className="flex-1 py-3 bg-stone-100 text-stone-700 rounded-xl font-bold hover:bg-stone-200 transition-colors">
                Cancel
              </button>
              <button onClick={handleSavePlace} disabled={!placeName2.trim() || !detectedLocation}
                className="flex-1 py-3 bg-indigo-600 text-white rounded-xl font-bold hover:bg-indigo-700 transition-colors disabled:opacity-40">
                Save Place
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
};

export default Location;
