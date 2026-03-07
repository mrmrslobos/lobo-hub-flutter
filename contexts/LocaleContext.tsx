import React, { createContext, useContext, useMemo } from 'react';
import {
  FamilySettings,
  DEFAULT_SETTINGS,
  localDateStr,
  fmtDate, fmtDateShort, fmtTime, fmtDateTime, fmtDateLong, fmtMonthYear,
  fmtCurrency, fmtCurrencyCompact, getCurrencySymbol,
  fmtWeight, weightUnit, kgToDisplay, displayToKg,
  fmtHeight, heightUnit, cmToDisplayVal, displayToCm,
  fmtDistance, distanceUnit, kmToDisplay,
} from '../services/locale';

export interface LocaleContextValue {
  settings: FamilySettings;

  // Dates & times
  fmtDate: (d: Date) => string;
  fmtDateShort: (d: Date) => string;
  fmtTime: (d: Date) => string;
  fmtDateTime: (d: Date) => string;
  fmtDateLong: (d: Date) => string;
  fmtMonthYear: (d: Date) => string;
  /** Today as 'yyyy-MM-dd' in the family's timezone — replaces toISOString().split('T')[0] */
  todayStr: () => string;

  // Currency
  fmtCurrency: (amount: number) => string;
  fmtCurrencyCompact: (amount: number) => string;
  currencySymbol: string;

  // Weight (DB stores kg)
  fmtWeight: (kg: number) => string;
  weightUnit: string;
  kgToDisplay: (kg: number) => number;
  displayToKg: (value: number) => number;

  // Height (DB stores cm)
  fmtHeight: (cm: number) => string;
  heightUnit: string;
  cmToDisplayVal: (cm: number) => number;
  displayToCm: (value: number) => number;

  // Distance (DB stores km)
  fmtDistance: (km: number) => string;
  distanceUnit: string;
  kmToDisplay: (km: number) => number;
}

const LocaleContext = createContext<LocaleContextValue>(buildValue(DEFAULT_SETTINGS));

function buildValue(s: FamilySettings): LocaleContextValue {
  return {
    settings: s,
    fmtDate: (d) => fmtDate(d, s),
    fmtDateShort: (d) => fmtDateShort(d, s),
    fmtTime: (d) => fmtTime(d, s),
    fmtDateTime: (d) => fmtDateTime(d, s),
    fmtDateLong: (d) => fmtDateLong(d, s),
    fmtMonthYear: (d) => fmtMonthYear(d, s),
    todayStr: () => localDateStr(s.timezone),
    fmtCurrency: (a) => fmtCurrency(a, s),
    fmtCurrencyCompact: (a) => fmtCurrencyCompact(a, s),
    currencySymbol: getCurrencySymbol(s),
    fmtWeight: (kg) => fmtWeight(kg, s),
    weightUnit: weightUnit(s),
    kgToDisplay: (kg) => kgToDisplay(kg, s),
    displayToKg: (v) => displayToKg(v, s),
    fmtHeight: (cm) => fmtHeight(cm, s),
    heightUnit: heightUnit(s),
    cmToDisplayVal: (cm) => cmToDisplayVal(cm, s),
    displayToCm: (v) => displayToCm(v, s),
    fmtDistance: (km) => fmtDistance(km, s),
    distanceUnit: distanceUnit(s),
    kmToDisplay: (km) => kmToDisplay(km, s),
  };
}

export const LocaleProvider: React.FC<{
  settings?: FamilySettings;
  children: React.ReactNode;
}> = ({ settings, children }) => {
  const value = useMemo(() => buildValue(settings ?? DEFAULT_SETTINGS), [settings]);
  return (
    <LocaleContext.Provider value={value}>
      {children}
    </LocaleContext.Provider>
  );
};

export const useLocale = (): LocaleContextValue => useContext(LocaleContext);
