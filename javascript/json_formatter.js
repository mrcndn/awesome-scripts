#!/usr/bin/env node

const fs = require('fs');

function formatJSON(input) {
  try {
    const obj = JSON.parse(input);
    console.log(JSON.stringify(obj, null, 2));
  } catch (e) {
    console.error('Error: Invalid JSON input');
    process.exit(1);
  }
}

// Check if input is from stdin or file
if (process.stdin.isTTY) {
  // Read from file argument
  if (process.argv.length < 3) {
    console.log('Usage: node json_formatter.js <file.json> OR cat file.json | node json_formatter.js');
    process.exit(1);
  }
  
  const filename = process.argv[2];
  fs.readFile(filename, 'utf8', (err, data) => {
    if (err) {
      console.error(`Error reading file: ${err.message}`);
      process.exit(1);
    }
    formatJSON(data);
  });
} else {
  // Read from stdin
  let data = '';
  process.stdin.on('data', chunk => {
    data += chunk;
  });
  
  process.stdin.on('end', () => {
    formatJSON(data);
  });
}
