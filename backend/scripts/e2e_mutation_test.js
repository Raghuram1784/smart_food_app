// E2E catalog mutation test: modify a DB record, verify via REST API, then restore.
// Usage: node scripts/e2e_mutation_test.js
require('dotenv').config({ path: __dirname + '/../.env' });
const pg = require('pg');
const http = require('http');

const DB_URL = process.env.DATABASE_URL;
const API_BASE = `http://localhost:${process.env.PORT || 5000}/api/v1`;

function apiGet(path) {
  return new Promise((resolve, reject) => {
    http.get(`${API_BASE}/${path}`, (res) => {
      let body = '';
      res.on('data', chunk => body += chunk);
      res.on('end', () => {
        const parsed = JSON.parse(body);
        resolve(parsed.data);
      });
    }).on('error', reject);
  });
}

async function main() {
  const client = new pg.Client({ connectionString: DB_URL });
  await client.connect();

  try {
    // 1. Record original price
    const before = await apiGet('menu-items/dosa');
    console.log(`[1] BEFORE update: id=dosa basePricePaise=${before.basePricePaise} imageKey=${before.imageKey}`);

    // 2. Mutate price in PostgreSQL
    await client.query('UPDATE "MenuItem" SET "basePricePaise" = 99900, "updatedAt" = now() WHERE id = $1', ['dosa']);
    console.log(`[2] PostgreSQL updated: dosa basePricePaise set to 99900`);

    // 3. Verify API reflects change
    const after = await apiGet('menu-items/dosa');
    console.log(`[3] AFTER update:  id=dosa basePricePaise=${after.basePricePaise}`);
    if (after.basePricePaise !== 99900) throw new Error(`Expected 99900, got ${after.basePricePaise}`);
    console.log(`[3] ✓ API reflected PostgreSQL change correctly`);

    // 4. Restore original price
    await client.query('UPDATE "MenuItem" SET "basePricePaise" = $1, "updatedAt" = now() WHERE id = $2', [before.basePricePaise, 'dosa']);
    console.log(`[4] PostgreSQL restored: dosa basePricePaise = ${before.basePricePaise}`);

    // 5. Verify restored
    const restored = await apiGet('menu-items/dosa');
    console.log(`[5] RESTORED:       id=dosa basePricePaise=${restored.basePricePaise}`);
    if (restored.basePricePaise !== before.basePricePaise) throw new Error('Restore failed');
    console.log(`[5] ✓ Price restored and API confirmed`);

    console.log('\n✓ E2E mutation test PASSED — PostgreSQL is the authoritative source.');
  } finally {
    await client.end();
  }
}

main().catch(err => { console.error('E2E test FAILED:', err.message); process.exitCode = 1; });

