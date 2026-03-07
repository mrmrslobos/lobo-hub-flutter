#!/usr/bin/env node
// Fixes deprecated proguard-android.txt -> proguard-android-optimize.txt
// in ALL node_modules build.gradle files (including nested deps).
const fs = require('fs');
const path = require('path');

const OLD = "getDefaultProguardFile('proguard-android.txt')";
const NEW = "getDefaultProguardFile('proguard-android-optimize.txt')";

function walk(dir) {
  if (!fs.existsSync(dir)) return;
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      walk(full);
    } else if (entry.name === 'build.gradle') {
      const src = fs.readFileSync(full, 'utf8');
      if (src.includes(OLD)) {
        fs.writeFileSync(full, src.replaceAll(OLD, NEW));
        console.log('Fixed:', full);
      }
    }
  }
}

walk(path.join(__dirname, '..', 'node_modules'));
