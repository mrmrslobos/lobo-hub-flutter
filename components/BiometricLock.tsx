/**
 * BiometricLock — app-level screen lock.
 *
 * On native (iOS / Android Capacitor) it uses the device's native biometric
 * prompt via @aparajita/capacitor-biometric-auth (Face ID, Touch ID, fingerprint).
 *
 * On web it falls back to WebAuthn (fingerprint / Face ID in the browser).
 *
 * If neither is available a numeric PIN fallback is offered.
 *
 * HOW IT WORKS
 * ────────────
 * 1. On first setup (via the Settings modal) biometric availability is checked.
 *    - Native: BiometricAuth.checkBiometry() — uses OS-level biometrics.
 *    - Web:    WebAuthn credential is registered with userVerification:'required'.
 * 2. On each unlock attempt the OS prompts for biometrics/PIN.
 * 3. PIN fallback is offered when biometrics are unavailable.
 */

import React, { useState, useEffect, useCallback } from 'react';
import { Fingerprint, KeyRound, Eye, EyeOff, Sparkles, ShieldCheck } from 'lucide-react';
import { Capacitor } from '@capacitor/core';
import {
  BiometricAuth,
  BiometryError,
  BiometryErrorType,
} from '@aparajita/capacitor-biometric-auth';
import { APP_CONFIG } from '../appConfig';

// ---------------------------------------------------------------------------
// Storage keys
// ---------------------------------------------------------------------------
const LOCK_ENABLED_KEY    = 'lobohub_lock_enabled';
const CREDENTIAL_ID_KEY   = 'lobohub_lock_credential_id'; // 'native' or base64url WebAuthn id
const LOCK_PIN_KEY        = 'lobohub_lock_pin_hash';      // SHA-256 of PIN

const isNative = Capacitor.isNativePlatform();

// ---------------------------------------------------------------------------
// WebAuthn helpers (web only)
// ---------------------------------------------------------------------------

function base64urlEncode(buffer: ArrayBuffer): string {
  const bytes = new Uint8Array(buffer);
  let str = '';
  bytes.forEach(b => (str += String.fromCharCode(b)));
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=/g, '');
}

function base64urlDecode(str: string): Uint8Array {
  const b64 = str.replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(b64);
  const arr = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) arr[i] = bin.charCodeAt(i);
  return arr;
}

function randomBytes(n: number): Uint8Array {
  const arr = new Uint8Array(n);
  crypto.getRandomValues(arr);
  return arr;
}

async function sha256(str: string): Promise<string> {
  const buf = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(str));
  return Array.from(new Uint8Array(buf)).map(b => b.toString(16).padStart(2, '0')).join('');
}

function isWebAuthnSupported(): boolean {
  return !!(window.PublicKeyCredential && navigator.credentials);
}

async function hasPlatformAuthenticator(): Promise<boolean> {
  if (!isWebAuthnSupported()) return false;
  try {
    return await (PublicKeyCredential as any).isUserVerifyingPlatformAuthenticatorAvailable();
  } catch {
    return false;
  }
}

async function registerWebAuthn(userId: string, userName: string): Promise<string> {
  const challenge = randomBytes(32);
  const rpId = window.location.hostname || 'localhost';
  const credential = await navigator.credentials.create({
    publicKey: {
      challenge,
      rp: { name: APP_CONFIG.appName, id: rpId },
      user: {
        id: new TextEncoder().encode(userId),
        name: userName,
        displayName: userName,
      },
      pubKeyCredParams: [
        { type: 'public-key', alg: -7 },   // ES256
        { type: 'public-key', alg: -257 },  // RS256
      ],
      authenticatorSelection: {
        authenticatorAttachment: 'platform',
        userVerification: 'required',
        residentKey: 'preferred',
      },
      timeout: 60000,
      attestation: 'none',
    },
  }) as PublicKeyCredential | null;

  if (!credential) throw new Error('No credential returned');
  return base64urlEncode(credential.rawId);
}

async function verifyWebAuthn(credentialId: string): Promise<boolean> {
  const challenge = randomBytes(32);
  const rpId = window.location.hostname || 'localhost';
  try {
    const credential = await navigator.credentials.get({
      publicKey: {
        challenge,
        allowCredentials: [{ id: base64urlDecode(credentialId), type: 'public-key' }],
        userVerification: 'required',
        timeout: 60000,
        rpId,
      },
    }) as PublicKeyCredential | null;
    return !!credential;
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Native biometric helpers (Capacitor iOS / Android)
// ---------------------------------------------------------------------------

async function isNativeBiometricAvailable(): Promise<boolean> {
  try {
    const result = await BiometricAuth.checkBiometry();
    return result.isAvailable;
  } catch {
    return false;
  }
}

async function verifyNativeBiometric(): Promise<boolean> {
  try {
    await BiometricAuth.authenticate({
      reason: `Unlock ${APP_CONFIG.appName}`,
      cancelTitle: 'Cancel',
      allowDeviceCredential: false,
    });
    return true;
  } catch (err) {
    // User cancelled or too many failures → don't throw, just return false
    return false;
  }
}

// ---------------------------------------------------------------------------
// Public helpers — used by the Settings modal to enable / disable lock
// ---------------------------------------------------------------------------

export function isLockEnabled(): boolean {
  return localStorage.getItem(LOCK_ENABLED_KEY) === '1';
}

export async function enableBiometricLock(
  userId: string,
  userName: string,
): Promise<{ method: 'biometric' | 'pin'; pin?: string; biometricUnavailable?: boolean }> {
  // ── Native path ──────────────────────────────────────────────────────────
  if (isNative) {
    const available = await isNativeBiometricAvailable();
    if (available) {
      localStorage.setItem(CREDENTIAL_ID_KEY, 'native');
      localStorage.setItem(LOCK_ENABLED_KEY, '1');
      return { method: 'biometric' };
    }
    // No biometrics enrolled on device → PIN fallback
    const pin = Array.from(randomBytes(4)).map(b => b % 10).join('');
    const hash = await sha256(pin);
    localStorage.setItem(LOCK_PIN_KEY, hash);
    localStorage.setItem(LOCK_ENABLED_KEY, '1');
    return { method: 'pin', pin, biometricUnavailable: true };
  }

  // ── Web path (WebAuthn) ──────────────────────────────────────────────────
  const platformAuthAvailable = await hasPlatformAuthenticator();
  if (platformAuthAvailable) {
    try {
      const credId = await registerWebAuthn(userId, userName);
      localStorage.setItem(CREDENTIAL_ID_KEY, credId);
      localStorage.setItem(LOCK_ENABLED_KEY, '1');
      return { method: 'biometric' };
    } catch (err) {
      console.warn('[BiometricLock] WebAuthn registration failed, offering PIN fallback:', err);
    }
  }

  // PIN fallback
  const pin = Array.from(randomBytes(4)).map(b => b % 10).join('');
  const hash = await sha256(pin);
  localStorage.setItem(LOCK_PIN_KEY, hash);
  localStorage.setItem(LOCK_ENABLED_KEY, '1');
  return { method: 'pin', pin, biometricUnavailable: !platformAuthAvailable };
}

export function disableLock() {
  localStorage.removeItem(LOCK_ENABLED_KEY);
  localStorage.removeItem(CREDENTIAL_ID_KEY);
  localStorage.removeItem(LOCK_PIN_KEY);
}

// ---------------------------------------------------------------------------
// BiometricLock component
// ---------------------------------------------------------------------------

interface BiometricLockProps {
  onUnlock: () => void;
}

const BiometricLock: React.FC<BiometricLockProps> = ({ onUnlock }) => {
  const [mode, setMode] = useState<'idle' | 'authenticating' | 'pin' | 'error'>('idle');
  const [pin, setPin] = useState('');
  const [showPin, setShowPin] = useState(false);
  const [errorMsg, setErrorMsg] = useState('');
  const [confirmReset, setConfirmReset] = useState(false);
  const [pinAttempts, setPinAttempts] = useState(0);

  const credentialId = localStorage.getItem(CREDENTIAL_ID_KEY);
  const hasCredential = !!credentialId;
  const hasPinHash    = !!localStorage.getItem(LOCK_PIN_KEY);

  const handleResetLock = () => {
    disableLock();
    onUnlock();
  };

  const attemptBiometric = useCallback(async () => {
    if (!credentialId) { setMode('pin'); return; }

    setMode('authenticating');
    setErrorMsg('');

    try {
      let ok = false;

      if (isNative && credentialId === 'native') {
        // ── Native biometric prompt ──────────────────────────────────────
        ok = await verifyNativeBiometric();
        if (!ok) {
          setErrorMsg('Authentication failed or was cancelled.');
          setMode('error');
          return;
        }
      } else if (!isNative) {
        // ── WebAuthn ────────────────────────────────────────────────────
        ok = await verifyWebAuthn(credentialId);
        if (!ok) {
          setErrorMsg('Authentication failed. Please try again.');
          setMode('error');
          return;
        }
      } else {
        // Credential stored but running native — shouldn't normally happen.
        // Offer PIN if there's one, otherwise reset.
        setErrorMsg('Biometric not available. Use your PIN instead.');
        setMode(hasPinHash ? 'pin' : 'error');
        return;
      }

      onUnlock();
    } catch (err: any) {
      if (err?.name === 'NotAllowedError') {
        setErrorMsg('Authentication was cancelled.');
      } else {
        setErrorMsg('Biometric not available. Use your PIN instead.');
        setMode('pin');
        return;
      }
      setMode('error');
    }
  }, [credentialId, hasPinHash, onUnlock]);

  // Auto-prompt on mount
  useEffect(() => {
    if (hasCredential) {
      if (isNative || isWebAuthnSupported()) {
        attemptBiometric();
      } else {
        setMode('pin');
      }
    } else {
      setMode('pin');
    }
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  const handlePinSubmit = async (e: React.FormEvent) => {
    e.preventDefault();
    const stored = localStorage.getItem(LOCK_PIN_KEY);
    if (!stored) {
      setErrorMsg('PIN data was lost. Use biometric or reset the lock.');
      return;
    }
    if (pinAttempts >= 10) {
      setErrorMsg('Too many attempts. Please reset the lock or use biometric.');
      return;
    }
    const hash = await sha256(pin);
    if (hash === stored) {
      onUnlock();
    } else {
      const attempts = pinAttempts + 1;
      setPinAttempts(attempts);
      setErrorMsg(attempts >= 10
        ? 'Too many attempts. Please reset the lock or use biometric.'
        : `Incorrect PIN. ${10 - attempts} attempts remaining.`);
      setPin('');
    }
  };

  const canUseBiometric = hasCredential && (isNative || isWebAuthnSupported());

  return (
    <div className="fixed inset-0 z-[9999] flex flex-col items-center justify-center bg-[#0f0f14] select-none">
      {/* Background decoration */}
      <div className="absolute inset-0 overflow-hidden pointer-events-none">
        <div className="absolute -top-32 -left-32 w-96 h-96 bg-indigo-600/20 rounded-full blur-3xl" />
        <div className="absolute -bottom-32 -right-32 w-96 h-96 bg-violet-600/20 rounded-full blur-3xl" />
      </div>

      <div className="relative z-10 flex flex-col items-center gap-8 w-full max-w-sm px-6">
        {/* Logo */}
        <div className="flex flex-col items-center gap-3">
          <div className="w-20 h-20 bg-indigo-600 rounded-3xl flex items-center justify-center shadow-2xl shadow-indigo-900/50">
            <Sparkles size={40} className="text-white" />
          </div>
          <h1 className="text-2xl font-black text-white">{APP_CONFIG.appName}</h1>
          <div className="flex items-center gap-2 text-stone-400 text-sm">
            <ShieldCheck size={14} />
            <span>App is locked</span>
          </div>
        </div>

        {mode === 'idle' || mode === 'authenticating' ? (
          <div className="flex flex-col items-center gap-4 w-full">
            <div className={`w-20 h-20 rounded-full border-2 flex items-center justify-center transition-all ${
              mode === 'authenticating'
                ? 'border-indigo-400 animate-pulse bg-indigo-900/30'
                : 'border-stone-600 bg-stone-800/50'
            }`}>
              <Fingerprint size={36} className={mode === 'authenticating' ? 'text-indigo-400' : 'text-stone-400'} />
            </div>
            <p className="text-stone-300 text-sm text-center">
              {mode === 'authenticating'
                ? 'Waiting for biometric…'
                : 'Tap to unlock with Face ID / Touch ID'}
            </p>
            {mode !== 'authenticating' && (
              <button
                onClick={attemptBiometric}
                className="px-8 py-3 bg-indigo-600 text-white rounded-2xl font-bold hover:bg-indigo-700 transition-colors shadow-lg shadow-indigo-900/50"
              >
                Unlock
              </button>
            )}
            {(hasPinHash || !hasCredential) && (
              <button onClick={() => setMode('pin')} className="text-stone-500 text-sm hover:text-stone-300 transition-colors">
                Use PIN instead
              </button>
            )}
          </div>
        ) : mode === 'error' ? (
          <div className="flex flex-col items-center gap-4 w-full">
            <p className="text-red-400 text-sm text-center bg-red-950/30 border border-red-900/30 rounded-2xl px-4 py-3">
              {errorMsg}
            </p>
            <button
              onClick={attemptBiometric}
              className="px-8 py-3 bg-indigo-600 text-white rounded-2xl font-bold hover:bg-indigo-700 transition-colors"
            >
              Try Again
            </button>
            {(hasPinHash || !hasCredential) && (
              <button
                onClick={() => { setMode('pin'); setErrorMsg(''); }}
                className="text-stone-500 text-sm hover:text-stone-300 transition-colors"
              >
                Use PIN instead
              </button>
            )}
            <button
              onClick={() => setConfirmReset(true)}
              className="text-stone-600 text-xs hover:text-stone-400 transition-colors mt-1"
            >
              Forgot PIN? Reset lock
            </button>
          </div>
        ) : (
          /* PIN mode */
          <form onSubmit={handlePinSubmit} className="flex flex-col items-center gap-4 w-full">
            <div className="flex items-center gap-2 text-stone-300">
              <KeyRound size={18} />
              <span className="font-semibold">Enter your PIN</span>
            </div>
            <div className="relative w-full">
              <input
                type={showPin ? 'text' : 'password'}
                inputMode="numeric"
                pattern="[0-9]*"
                maxLength={8}
                value={pin}
                onChange={(e) => setPin(e.target.value.replace(/\D/g, ''))}
                autoFocus
                className="w-full px-4 py-4 bg-stone-800 border border-stone-600 rounded-2xl text-white text-center text-2xl font-bold tracking-[0.5em] focus:outline-none focus:ring-2 focus:ring-indigo-500 placeholder:text-stone-600"
                placeholder="••••"
              />
              <button
                type="button"
                onClick={() => setShowPin(v => !v)}
                className="absolute right-4 top-1/2 -translate-y-1/2 text-stone-400 hover:text-stone-200"
              >
                {showPin ? <EyeOff size={18} /> : <Eye size={18} />}
              </button>
            </div>
            {errorMsg && (
              <p className="text-red-400 text-sm text-center">{errorMsg}</p>
            )}
            <button
              type="submit"
              disabled={pin.length < 4}
              className="w-full py-3 bg-indigo-600 text-white rounded-2xl font-bold hover:bg-indigo-700 transition-colors disabled:opacity-40"
            >
              Unlock
            </button>
            {canUseBiometric && (
              <button
                type="button"
                onClick={() => { setMode('idle'); setErrorMsg(''); setPin(''); }}
                className="text-stone-500 text-sm hover:text-stone-300 transition-colors flex items-center gap-2"
              >
                <Fingerprint size={14} />Use biometric instead
              </button>
            )}
            <button
              type="button"
              onClick={() => setConfirmReset(true)}
              className="text-stone-600 text-xs hover:text-stone-400 transition-colors mt-2"
            >
              Forgot PIN? Reset lock
            </button>
          </form>
        )}

        {/* Reset lock confirmation */}
        {confirmReset && (
          <div className="fixed inset-0 z-[10000] flex items-center justify-center bg-black/70 px-6">
            <div className="bg-stone-900 border border-stone-700 rounded-3xl p-6 w-full max-w-xs text-center space-y-4">
              <p className="text-white font-bold">Reset App Lock?</p>
              <p className="text-stone-400 text-sm">
                This will disable the lock and let you back in. You can re-enable it in Settings.
              </p>
              <div className="flex gap-3">
                <button
                  onClick={() => setConfirmReset(false)}
                  className="flex-1 py-2.5 bg-stone-800 text-stone-300 rounded-xl font-semibold hover:bg-stone-700 transition-colors text-sm"
                >
                  Cancel
                </button>
                <button
                  onClick={handleResetLock}
                  className="flex-1 py-2.5 bg-red-600 text-white rounded-xl font-semibold hover:bg-red-700 transition-colors text-sm"
                >
                  Reset Lock
                </button>
              </div>
            </div>
          </div>
        )}
      </div>
    </div>
  );
};

export default BiometricLock;
